const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const express = require('express');
const jwt = require('jsonwebtoken');
const User = require('../src/models/User');
const Booking = require('../src/models/Booking');
const Account = require('../src/models/WalletAccount');
const Entry = require('../src/models/WalletEntry');
const Payment = require('../src/models/WalletPayment');
const Settings = require('../src/models/Settings');
const Device = require('../src/models/NotificationDevice');
const Delivery = require('../src/models/PushDelivery');
const Credential = require('../src/models/NotificationCredential');
const { money, adminCredit, reviewPayment } = require('../src/services/wallet');
const { saveBooking } = require('../src/services/dailyBookingLimit');
const notifications = require('../src/services/paymentNotifications');
let mongo, server, base;
const models = [User, Booking, Account, Entry, Payment, Settings, Device, Delivery, Credential];
before(async () => {
  mongo = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  await mongoose.connect(mongo.getUri());
  await Promise.all(models.map(m => m.init()));
  process.env.JWT_SECRET = 'local-test-only-not-production';
  const app = express(); app.use(express.json({ limit: '2mb' }));
  app.use('/api/wallet', require('../src/routes/wallet'));
  app.use('/api/bookings', require('../src/routes/bookings'));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => { await new Promise(resolve => server.close(resolve)); await mongoose.disconnect(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all(models.map(m => m.deleteMany({})));
  await User.create([
    { username: 'admin', role: 'ADMIN', passwordHash: 'test-only' },
    { username: 'agent', role: 'AGENT', passwordHash: 'test-only' },
    { username: 'other', role: 'CUSTOMER', passwordHash: 'test-only' },
  ]);
  delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
});
function bill(no, amount) { return { billNo: no, username: 'agent', ownerUsername: 'agent',
  rows: [{ number: '123', count: 1, amount }], createdAt: new Date(), deletedAt: null }; }
const save = (no, amount) => saveBooking(bill(no, amount), { billNo: no, ownerUsername: 'agent' });
async function request(path, body, user = 'admin', method = 'POST', role) {
  const token = jwt.sign({ username: user, role: role || (user === 'admin' ? 'ADMIN' : 'AGENT') }, process.env.JWT_SECRET);
  return fetch(base + path, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    ...(body ? { body: JSON.stringify(body) } : {}) });
}
const image = `data:image/png;base64,${Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), Buffer.alloc(20)]).toString('base64')}`;
async function payment(utr = 'TEST123456') {
  await Settings.create({ key: 'walletPayment', value: { phone: '0000000000', payeeName: 'Test' } });
  const response = await request('/api/wallet/payments', { amount: 200, utr, receipt: image, requestId: 'request_test_12345' }, 'agent');
  assert.equal(response.status, 201); return (await response.json()).id;
}
test('12000 credit minus 1000 booking leaves 11000, next day carries forward', async () => {
  await adminCredit('agent', 12000, 'admin', 'request_12345');
  await save(1, 1000); await save(1, 1000);
  let wallet = await Account.findOne({ username: 'agent' });
  assert.equal(wallet.balancePaise, 1100000); assert.equal(wallet.totalCreditPaise, 1200000);
  await Booking.updateOne({ billNo: 1 }, { createdAt: new Date(Date.now() - 86400000) });
  await save(2, 1000);
  wallet = await Account.findOne({ username: 'agent' });
  assert.equal(wallet.balancePaise, 1000000); assert.equal(wallet.bookedPaise, 200000);
});
test('concurrent phones cannot spend the same wallet balance', async () => {
  await adminCredit('agent', 100, 'admin', 'request_12345');
  const results = await Promise.allSettled([save(1, 80), save(2, 80)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal((await Account.findOne()).balancePaise, 2000);
  assert.equal(await Booking.countDocuments(), 1);
});
test('edits debit differences, deletion refunds only once', async () => {
  await adminCredit('agent', 200, 'admin', 'request_12345');
  await save(1, 100); await save(1, 150); await save(1, 80);
  assert.equal((await Account.findOne()).balancePaise, 12000);
  for (let i = 0; i < 2; i++) assert.equal((await request('/api/bookings/1', null, 'agent', 'DELETE')).status, 200);
  assert.equal((await Account.findOne()).balancePaise, 20000);
  assert.equal((await Account.findOne()).bookedPaise, 0);
});
test('legacy bookings never refund unfunded money', async () => {
  await save(1, 100); await adminCredit('agent', 200, 'admin', 'request_12345');
  await save(1, 150); assert.equal((await Account.findOne()).balancePaise, 15000);
  await request('/api/bookings/1', null, 'agent', 'DELETE');
  assert.equal((await Account.findOne()).balancePaise, 20000);
});
test('daily cap and wallet enforce independently', async () => {
  await User.updateOne({ username: 'agent' }, { amountLimit: 200 });
  await adminCredit('agent', 500, 'admin', 'request_12345');
  await save(1, 150); await assert.rejects(save(2, 60), { code: 'DAILY_AMOUNT_LIMIT' });
  assert.equal((await Account.findOne()).balancePaise, 35000);
  await User.updateOne({ username: 'agent' }, { amountLimit: 0 });
  await assert.rejects(save(2, 351), { code: 'WALLET_BALANCE' });
});
test('payment remains pending until approval, approval retries credit only once', async () => {
  const id = await payment(); assert.equal(await Account.countDocuments(), 0);
  await Promise.all([reviewPayment(id, 'admin', 'approved'), reviewPayment(id, 'admin', 'approved')]);
  assert.equal((await Account.findOne()).balancePaise, 20000);
  assert.equal(await Entry.countDocuments({ kind: 'payment' }), 1);
  await assert.rejects(reviewPayment(id, 'admin', 'rejected', 'No'), { status: 409 });
});
test('reject and min 200 validation; invalid amounts cannot change balance', async () => {
  for (const value of [null, '', true, -1, 1.001, Infinity, 'wrong']) assert.throws(() => money(value, 1));
  assert.throws(() => money(199.99, 20000));
  const id = await payment(); await assert.rejects(reviewPayment(id, 'admin', 'rejected'), { status: 400 });
  await reviewPayment(id, 'admin', 'rejected', 'Not received'); assert.equal(await Account.countDocuments(), 0);
});
test('UTR and request retries idempotent; global duplicate cannot be reused', async () => {
  const id = await payment();
  const body = { amount: 200, utr: 'TEST123456', receipt: image, requestId: 'request_test_12345' };
  assert.equal((await request('/api/wallet/payments', body, 'agent')).status, 201);
  assert.equal((await request('/api/wallet/payments', body, 'other')).status, 409);
  assert.equal(await Payment.countDocuments(), 1);
  assert.equal((await Payment.findById(id)).status, 'pending');
});
test('customer cannot view another wallet, receipts, give credit or spoof admin JWT role', async () => {
  const id = await payment();
  assert.equal((await request('/api/wallet?username=agent', null, 'other', 'GET')).status, 403);
  assert.equal((await request(`/api/wallet/payments/${id}/receipt`, null, 'other', 'GET')).status, 403);
  assert.equal((await request('/api/wallet/credit', { username: 'other', amount: 100, requestId: 'request_test_12345' }, 'other', 'POST', 'ADMIN')).status, 403);
  const list = await (await request('/api/wallet/admin', null, 'admin', 'GET')).json();
  assert.equal('receipt' in list.payments[0], false);
});
test('admin credit retries never duplicate and conflicting payload fails', async () => {
  await adminCredit('agent', 200, 'admin', 'request_12345'); await adminCredit('agent', 200, 'admin', 'request_12345');
  await assert.rejects(adminCredit('agent', 300, 'admin', 'request_12345'), { status: 409 });
  assert.equal((await Account.findOne()).balancePaise, 20000);
});
test('push sends only to active admins, persists retry after failure, avoids duplicate success', async () => {
  const id = await payment();
  await Device.create([{ username: 'admin', token: 'admin-token-test' }, { username: 'agent', token: 'agent-token-test' }]);
  let fail = true, sent = [];
  const sender = { send: async message => {
    assert.equal(message.token, 'admin-token-test'); assert.equal(message.android.priority, 'high');
    if (fail) throw Object.assign(new Error('test failure'), { code: 'messaging/server-unavailable' });
    sent.push(message); return 'test-message';
  } };
    await notifications.deliverPendingNotifications({ sender });
    assert.equal(await Delivery.countDocuments(), 1); assert.ok(!(await Delivery.findOne()).sentAt);
    fail = false; await Delivery.updateMany({}, { nextAttemptAt: new Date(0) });
    await notifications.deliverPendingNotifications({ sender }); await notifications.deliverPendingNotifications({ sender });
    assert.equal(sent.length, 1); assert.equal(`${sent[0].data.paymentId}`, id);
});
