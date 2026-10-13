const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const express = require('express');
const jwt = require('jsonwebtoken');
const User = require('../src/models/User');
const Account = require('../src/models/WalletAccount');
const Entry = require('../src/models/WalletEntry');
const Withdrawal = require('../src/models/WalletWithdrawal');
const Payment = require('../src/models/WalletPayment');
const Booking = require('../src/models/Booking');
const Settings = require('../src/models/Settings');
const Device = require('../src/models/NotificationDevice');
const Delivery = require('../src/models/WithdrawalPushDelivery');
const { adminCredit, reviewPayment } = require('../src/services/wallet');
const { requestWithdrawal, reviewWithdrawal } = require('../src/services/walletWithdrawals');
const { saveBooking } = require('../src/services/dailyBookingLimit');
const { deliverPendingNotifications } = require('../src/services/paymentNotifications');
const models = [User, Account, Entry, Withdrawal, Payment, Booking, Settings, Device, Delivery];
let mongo, server, base;
before(async () => {
  mongo = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  await mongoose.connect(mongo.getUri());
  await Promise.all(models.map(m => m.init()));
  process.env.JWT_SECRET = 'withdrawal-local-test-only';
  const app = express(); app.use(express.json()); app.use('/api/wallet', require('../src/routes/wallet'));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => { await new Promise(resolve => server.close(resolve)); await mongoose.disconnect(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(m => m.deleteMany({})));
  await User.create(['admin', 'secondadmin', 'customer', 'other'].map(username => ({ username,
    role: username.includes('admin') ? 'ADMIN' : 'CUSTOMER', passwordHash: 'test-only' })));
});
const body = (overrides = {}) => ({ amount: 200, payeeName: 'Test Customer', destinationType: 'upi',
  destination: 'test@bank', requestId: 'withdrawal_request_12345', ...overrides });
async function request(path = '/withdrawals', data = body(), username = 'customer', method = 'POST', role) {
  const token = jwt.sign({ username, role: role || (username.includes('admin') ? 'ADMIN' : 'CUSTOMER') }, process.env.JWT_SECRET);
  return fetch(base + '/api/wallet' + path, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    ...(data ? { body: JSON.stringify(data) } : {}) });
}
const create = (overrides = {}, username = 'customer') => requestWithdrawal(username, body(overrides), body(overrides).requestId);
const review = (id, action, overrides = {}, actor = 'admin') => reviewWithdrawal(id, actor, { action, ...overrides });
const funded = amount => adminCredit('customer', amount, 'admin', 'initial_wallet_funds');

test('500 payment minus 300 booking plus 1000 winnings permits withdrawal of the full 1200', async () => {
  const payment = await Payment.create({ username: 'customer', amountPaise: 50000, utr: 'DEPOSIT500',
    receipt: 'test-only', idempotencyKey: 'deposit_example_500' });
  await reviewPayment(payment._id, 'admin', 'approved');
  await saveBooking({ billNo: 1, username: 'customer', ownerUsername: 'customer',
    rows: [{ number: '123', count: 30, amount: 300 }], createdAt: new Date() }, { billNo: 1, ownerUsername: 'customer' });
  const account = await Account.findOneAndUpdate({ username: 'customer' },
    { $inc: { balancePaise: 100000, winningsPaise: 100000 } }, { new: true });
  await Entry.create({ username: 'customer', kind: 'winning', amountPaise: 100000,
    balanceAfterPaise: account.balancePaise, note: 'Test winning settlement' });
  const before = await (await request('', null, 'customer', 'GET')).json();
  assert.equal(before.balance, 1200); assert.equal(before.withdrawable, 1200);
  const response = await request('/withdrawals', body({ amount: 1200 }));
  assert.equal(response.status, 201);
  const after = await (await request('', null, 'customer', 'GET')).json();
  assert.equal(after.balance, 0); assert.equal(after.withdrawable, 0); assert.equal(after.withdrawalReserved, 1200);
  assert.equal(after.withdrawals.length, 1); assert.equal(after.withdrawn, 0);
});
test('repeat submission and retries after completion never deduct twice', async () => {
  await funded(500);
  const results = await Promise.all([create(), create(), create()]);
  assert.equal(new Set(results.map(r => `${r._id}`)).size, 1);
  assert.equal((await Account.findOne()).balancePaise, 30000);
  assert.equal(await Entry.countDocuments({ kind: 'withdrawal_hold' }), 1);
  await review(results[0]._id, 'rejected', { note: 'Test rejection' });
  assert.equal((await create()).status, 'rejected');
  assert.equal((await Account.findOne()).balancePaise, 50000);
});
test('changed amount or destination cannot reuse an existing request reference', async () => {
  await funded(500); await create();
  for (const changes of [{ amount: 201 }, { destination: 'other@bank' }, { payeeName: 'Another person' }]) {
    await assert.rejects(create(changes), e => e.status === 409);
  }
  assert.equal(await Withdrawal.countDocuments(), 1);
  assert.equal((await Account.findOne()).balancePaise, 30000);
});
test('concurrent different withdrawals and bookings cannot overspend the same wallet', async () => {
  await funded(1000);
  const booking = () => saveBooking({ billNo: 1, username: 'customer', ownerUsername: 'customer',
    rows: [{ number: '123', count: 80, amount: 800 }], createdAt: new Date() }, { billNo: 1, ownerUsername: 'customer' });
  const results = await Promise.allSettled([create({ amount: 800 }),
    create({ amount: 800, requestId: 'withdrawal_second_request' }), booking()]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal((await Account.findOne()).balancePaise, 20000);
  assert.equal(await Withdrawal.countDocuments() + await Booking.countDocuments(), 1);
});
test('reject and customer cancellation return the reservation exactly once', async () => {
  await funded(500); const first = await create();
  await Promise.all([review(first._id, 'rejected', { note: 'Invalid destination' }),
    review(first._id, 'rejected', { note: 'Invalid destination' })]);
  const second = await create({ requestId: 'customer_cancel_request' });
  await reviewWithdrawal(second._id, 'customer', { action: 'cancelled' }, { customer: true });
  await reviewWithdrawal(second._id, 'customer', { action: 'cancelled' }, { customer: true });
  const account = await Account.findOne();
  assert.equal(account.balancePaise, 50000); assert.equal(account.withdrawalReservedPaise, 0);
  assert.equal(await Entry.countDocuments({ kind: 'withdrawal_release' }), 2);
  await assert.rejects(review(first._id, 'approved'), e => e.status === 409);
});
test('approval claims one admin and does not transfer or further deduct money', async () => {
  await funded(500); const w = await create();
  const results = await Promise.allSettled([review(w._id, 'approved'), review(w._id, 'approved', {}, 'secondadmin')]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const stored = await Withdrawal.findById(w._id);
  assert.equal(stored.status, 'approved'); assert.ok(stored.approvedBy);
  assert.equal((await Account.findOne()).balancePaise, 30000);
  assert.equal((await Account.findOne()).withdrawalReservedPaise, 20000);
  await assert.rejects(reviewWithdrawal(w._id, 'customer', { action: 'cancelled' }, { customer: true }), e => e.status === 409);
  const otherAdmin = stored.approvedBy === 'admin' ? 'secondadmin' : 'admin';
  await assert.rejects(review(w._id, 'rejected', { note: 'Test' }, otherAdmin), e => e.status === 409);
});
test('paid requires approval and confirmed real transfer; payout is recorded without a second debit', async () => {
  await funded(500); const w = await create();
  await assert.rejects(review(w._id, 'paid', { confirmed: true, transferReference: 'TXN123456' }), e => e.status === 409);
  await review(w._id, 'approved');
  await assert.rejects(review(w._id, 'paid', { transferReference: 'TXN123456' }), e => e.status === 400);
  await assert.rejects(review(w._id, 'paid', { confirmed: true }), e => e.status === 400);
  await Promise.all([review(w._id, 'paid', { confirmed: true, transferReference: 'TXN123456' }),
    review(w._id, 'paid', { confirmed: true, transferReference: 'TXN123456' })]);
  const account = await Account.findOne();
  assert.equal(account.balancePaise, 30000); assert.equal(account.withdrawalReservedPaise, 0); assert.equal(account.withdrawnPaise, 20000);
  assert.equal(await Entry.countDocuments({ kind: 'withdrawal_paid' }), 1);
  assert.equal((await Entry.find()).reduce((sum, e) => sum + e.amountPaise, 0), account.balancePaise);
  await assert.rejects(review(w._id, 'paid', { confirmed: true, transferReference: 'DIFFERENT123' }), e => e.status === 409);
  await assert.rejects(review(w._id, 'rejected', { note: 'Test' }), e => e.status === 409);
});
test('a transfer reference cannot pay two withdrawals; conflicts roll back all wallet changes', async () => {
  await funded(500); const first = await create(); const second = await create({ requestId: 'withdrawal_second_request' });
  await review(first._id, 'approved'); await review(second._id, 'approved');
  await review(first._id, 'paid', { confirmed: true, transferReference: 'SAMEUPI123' });
  await assert.rejects(review(second._id, 'paid', { confirmed: true, transferReference: 'SAMEUPI123' }), e => e.status === 409);
  assert.equal((await Withdrawal.findById(second._id)).status, 'approved');
  const account = await Account.findOne();
  assert.equal(account.withdrawalReservedPaise, 20000); assert.equal(account.withdrawnPaise, 20000);
});
test('invalid amounts, destinations and overdraw never create reservations', async () => {
  await funded(500);
  for (const amount of [-10, 0, 500.01, '1.001', 'NaN', [], {}, true]) {
    const response = await request('/withdrawals', body({ amount }));
    assert.ok([400, 409].includes(response.status));
  }
  for (const changes of [{ destination: 'invalid' }, { destinationType: 'bank' },
    { destinationType: 'phone', destination: '1234567890' }, { payeeName: '' },
    { payeeName: 'line\nbreak' }, { requestId: 'short' }]) {
    assert.equal((await request('/withdrawals', body(changes))).status, 400);
  }
  assert.equal(await Withdrawal.countDocuments(), 0); assert.equal((await Account.findOne()).balancePaise, 50000);
  assert.equal((await request('/withdrawals', body({ destinationType: 'phone', destination: '9000000000' }))).status, 201);
});
test('customers cannot access another customer or spoof admin rights; blocked users cannot submit', async () => {
  await funded(500); const w = await create();
  assert.equal((await request(`/withdrawals/${w._id}`, null, 'other', 'GET')).status, 404);
  assert.equal((await request(`/withdrawals/${w._id}/cancel`, {}, 'other')).status, 404);
  assert.equal((await request(`/withdrawals/${w._id}/review`, { action: 'approved' }, 'other', 'POST', 'ADMIN')).status, 403);
  assert.equal((await request('/withdrawals', body(), 'admin')).status, 403);
  assert.equal((await request('/admin', null, 'customer', 'GET')).status, 403);
  await User.updateOne({ username: 'other' }, { isBlocked: true });
  assert.equal((await request('/withdrawals', body(), 'other')).status, 403);
  assert.equal((await request('/withdrawals/not-an-id', null, 'customer', 'GET')).status, 400);
});
test('legacy wallets acquire reservation fields without changing existing funds', async () => {
  await Account.collection.insertOne({ username: 'customer', enabled: true, balancePaise: 50000 });
  const w = await create(); await review(w._id, 'rejected', { note: 'Test' });
  assert.equal((await Account.findOne()).balancePaise, 50000);
  assert.equal((await Account.findOne()).withdrawalReservedPaise, 0);
});
test('a negative balance from result correction blocks approval and payment until resolved', async () => {
  await funded(500); const w = await create();
  await Account.updateOne({ username: 'customer' }, { balancePaise: -100 });
  await assert.rejects(review(w._id, 'approved'), e => e.status === 409);
  await Account.updateOne({ username: 'customer' }, { balancePaise: 30000 });
  await review(w._id, 'approved');
  await Account.updateOne({ username: 'customer' }, { balancePaise: -100 });
  await assert.rejects(review(w._id, 'paid', { confirmed: true, transferReference: 'CORRECTION123' }), e => e.status === 409);
  await review(w._id, 'rejected', { note: 'Wallet correction' });
  assert.equal((await Account.findOne()).balancePaise, 19900);
});
test('admin sees pending and approved withdrawals; completed withdrawals remain in customer history', async () => {
  await funded(500); const w = await create();
  await review(w._id, 'approved');
  let admin = await (await request('/admin', null, 'admin', 'GET')).json();
  assert.equal(admin.pendingWithdrawalCount, 1); assert.equal(admin.withdrawals[0].status, 'approved');
  await review(w._id, 'paid', { confirmed: true, transferReference: 'ADMINLIST123' });
  admin = await (await request('/admin', null, 'admin', 'GET')).json();
  assert.equal(admin.pendingWithdrawalCount, 0);
  const user = await (await request('', null, 'customer', 'GET')).json();
  assert.equal(user.withdrawals[0].status, 'paid'); assert.equal(user.withdrawn, 200);
});
test('withdrawal notification persists retry, sends only to active admins and deduplicates success', async () => {
  await funded(500); const w = await create();
  await Device.create([{ username: 'admin', token: 'withdrawal-admin-token' }, { username: 'customer', token: 'withdrawal-user-token' }]);
  let fail = true; const sent = [];
  const sender = { send: async message => {
    assert.equal(message.token, 'withdrawal-admin-token');
    if (fail) throw Object.assign(new Error('Test'), { code: 'messaging/server-unavailable' });
    sent.push(message);
  } };
  await deliverPendingNotifications({ sender });
  assert.equal(await Delivery.countDocuments(), 1); assert.ok(!(await Delivery.findOne()).sentAt);
  fail = false; await Delivery.updateMany({}, { nextAttemptAt: new Date(0) });
  await deliverPendingNotifications({ sender }); await deliverPendingNotifications({ sender });
  assert.equal(sent.length, 1); assert.equal(sent[0].data.type, 'wallet_withdrawal');
  assert.equal(sent[0].data.withdrawalId, `${w._id}`);
  assert.ok(!JSON.stringify(sent[0]).includes('test@bank'));
});
