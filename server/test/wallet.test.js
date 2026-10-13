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

test('booking POST returns committed wallet balance without a follow-up request', async () => {
  await adminCredit('agent', 200, 'admin', 'request_12345');
  await User.updateOne({ username: 'agent' }, { amountLimit: 150 });
  const payload = bill(501, 50);
  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await request('/api/bookings', payload, 'agent');
    assert.equal(response.status, 201);
    const saved = await response.json();
    assert.equal(saved.wallet.balance, 150);
    assert.equal(saved.wallet.booked, 50);
    assert.equal(saved.wallet.totalCredit, 200);
    assert.equal(saved.wallet.withdrawable, 150);
    assert.equal(saved.amountLimit, 150);
  }
  assert.equal(await Booking.countDocuments(), 1);
  assert.equal(await Entry.countDocuments({ kind: 'booking' }), 1);
  const stored = await Booking.findOne({ billNo: 501 }).lean();
  assert.equal('walletSnapshot' in stored, false);
  assert.equal('$locals' in stored, false);
});

test('single booking POST still rejects daily-limit and wallet overspending', async () => {
  await adminCredit('agent', 200, 'admin', 'request_12345');
  await User.updateOne({ username: 'agent' }, { amountLimit: 100 });
  let response = await request('/api/bookings', bill(502, 101), 'agent');
  assert.equal(response.status, 409);
  assert.equal((await response.json()).code, 'DAILY_AMOUNT_LIMIT');
  await User.updateOne({ username: 'agent' }, { amountLimit: 0 });
  response = await request('/api/bookings', bill(502, 201), 'agent');
  assert.equal(response.status, 409);
  assert.equal((await response.json()).code, 'WALLET_BALANCE');
  assert.equal(await Booking.countDocuments(), 0);
  assert.equal((await Account.findOne({ username: 'agent' })).balancePaise, 20000);
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

const manualBody = (extra = {}) => ({ username: 'agent', amount: 200,
  utr: 'MANUALTEST123', requestId: 'manual_request_12345', confirmed: true, ...extra });
const manual = body => request('/api/wallet/payments/manual', body);

test('admin can credit a verified WhatsApp payment with UTR and an audit record', async () => {
  const response = await manual(manualBody({ note: 'Received through WhatsApp' }));
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.balance, 200);
  assert.equal(result.alreadyCredited, false);
  const p = await Payment.findById(result.paymentId);
  assert.equal(p.source, 'whatsapp'); assert.equal(p.status, 'approved');
  assert.equal(p.reviewedBy, 'admin'); assert.equal(p.submittedBy, 'admin');
  assert.ok(p.reviewedAt); assert.equal(p.reviewNote, 'Received through WhatsApp');
  const entry = await Entry.findOne({ paymentId: p._id });
  assert.equal(entry.actor, 'admin'); assert.equal(entry.amountPaise, 20000);
  assert.match(entry.note, /WhatsApp payment.*MANUALTEST123/);
  assert.equal(await Payment.countDocuments({ status: 'pending' }), 0);
});

test('screenshot-only WhatsApp payment credits once, including a different retry request', async () => {
  const body = manualBody({ utr: '', receipt: image });
  assert.equal((await manual(body)).status, 200);
  const retry = await manual({ ...body, requestId: 'manual_request_second' });
  assert.equal(retry.status, 200); assert.equal((await retry.json()).alreadyCredited, true);
  assert.equal((await Account.findOne()).balancePaise, 20000);
  assert.equal(await Entry.countDocuments(), 1); assert.equal(await Payment.countDocuments(), 1);
  assert.equal((await Payment.findOne()).utrIsGenerated, true);
  assert.equal((await manual({ ...body, username: 'other' })).status, 409);
});

test('WhatsApp verification approves an existing in-app request without a second credit', async () => {
  const id = await payment('MANUALTEST123');
  const response = await manual(manualBody());
  assert.equal(response.status, 200); assert.equal((await response.json()).paymentId, id);
  assert.equal((await Payment.findById(id)).status, 'approved');
  await reviewPayment(id, 'admin', 'approved');
  const retried = await manual(manualBody({ requestId: 'manual_new_request' }));
  assert.equal((await retried.json()).alreadyCredited, true);
  assert.equal(await Payment.countDocuments(), 1); assert.equal(await Entry.countDocuments(), 1);
  assert.equal((await Account.findOne()).balancePaise, 20000);
});

test('legacy screenshots and new in-app submissions cannot double-credit a manual payment', async () => {
  const id = await payment('LEGACY123456');
  await Payment.updateOne({ _id: id }, { $unset: { receiptHash: 1 } });
  await reviewPayment(id, 'admin', 'approved');
  const response = await manual(manualBody({ utr: '', receipt: image }));
  assert.equal(response.status, 200); assert.equal((await response.json()).alreadyCredited, true);
  assert.equal((await Account.findOne()).balancePaise, 20000);
  assert.equal(await Entry.countDocuments(), 1);
});

test('customer submissions cannot reuse a screenshot credited through WhatsApp', async () => {
  assert.equal((await manual(manualBody({ utr: '', receipt: image }))).status, 200);
  await Settings.create({ key: 'walletPayment', value: { phone: '0000000000', payeeName: 'Test' } });
  const response = await request('/api/wallet/payments', {
    amount: 200, utr: 'NEWAPP12345', receipt: image, requestId: 'customer_new_request',
  }, 'agent');
  assert.equal(response.status, 409);
  assert.equal((await Account.findOne()).balancePaise, 20000);
  assert.equal(await Payment.countDocuments(), 1);
});

test('concurrent duplicate UTR across two wallets credits exactly one wallet', async () => {
  const responses = await Promise.all([
    manual(manualBody()),
    manual(manualBody({ username: 'other', requestId: 'other_manual_request' })),
  ]);
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 409]);
  assert.equal(await Account.countDocuments(), 1); assert.equal(await Entry.countDocuments(), 1);
  assert.equal((await Account.findOne()).balancePaise, 20000);
});

test('manual payment rejects invalid, unconfirmed, rejected and conflicting credit requests', async () => {
  for (const body of [manualBody({ amount: 199.99 }), manualBody({ amount: -200 }),
    manualBody({ amount: '200.001' }), manualBody({ utr: '' }),
    manualBody({ confirmed: false }), manualBody({ note: 'x'.repeat(301) }),
    manualBody({ receipt: 'invalid' }), manualBody({ username: 'admin' })]) {
    assert.equal((await manual(body)).status, 400);
  }
  assert.equal(await Account.countDocuments(), 0);
  const id = await payment('REJECTED123'); await reviewPayment(id, 'admin', 'rejected', 'Not received');
  assert.equal((await manual(manualBody({ utr: 'REJECTED123' }))).status, 409);
  assert.equal((await manual(manualBody())).status, 200);
  assert.equal((await manual(manualBody({ amount: 300 }))).status, 409);
  assert.equal((await manual(manualBody({ utr: 'CHANGED1234' }))).status, 409);
  assert.equal((await manual(manualBody({ username: 'other', utr: 'CHANGED1234' }))).status, 409);
  assert.equal(await Account.countDocuments(), 1);
  assert.equal((await Account.findOne()).balancePaise, 20000);
});

test('manual payment cannot be called by a customer or a spoofed admin JWT role', async () => {
  const response = await request('/api/wallet/payments/manual', manualBody(), 'other', 'POST', 'ADMIN');
  assert.equal(response.status, 403);
  assert.equal(await Payment.countDocuments(), 0); assert.equal(await Account.countDocuments(), 0);
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
