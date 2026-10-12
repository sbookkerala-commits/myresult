const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const express = require('express');
const jwt = require('jsonwebtoken');
const User = require('../src/models/User');
const Booking = require('../src/models/Booking');
const { dayWindow, rowsPaise, usedPaise, saveBooking } = require('../src/services/dailyBookingLimit');
let mongo, server, base;

before(async () => {
  mongo = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  await mongoose.connect(mongo.getUri());
  await Promise.all([User.init(), Booking.init()]);
  process.env.JWT_SECRET = 'local-test-only-not-a-production-secret';
  const app = express();
  app.use(express.json());
  app.use('/api/bookings', require('../src/routes/bookings'));
  app.use('/api/users', require('../src/routes/users'));
  app.use('/api/settings', require('../src/routes/settings'));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  if (server) await new Promise(resolve => server.close(resolve));
  await mongoose.disconnect();
  if (mongo) await mongo.stop();
});
beforeEach(async () => {
  await Promise.all([User.deleteMany({}), Booking.deleteMany({})]);
  await User.create({ username: 'agent', passwordHash: 'unused-test-hash', role: 'AGENT', amountLimit: 200 });
});
function doc(billNo, amount, drawName = 'DEAR 1 PM') {
  return { billNo, username: 'agent', ownerUsername: 'agent', createdAt: new Date(),
    rows: [{ number: '123', count: '1', amount }], drawName, deletedAt: null };
}
async function save(id, amount, draw) { return saveBooking(doc(id, amount, draw), { billNo: id, ownerUsername: 'agent' }); }
async function request(path, body, method = 'POST', role = 'ADMIN') {
  const token = jwt.sign({ username: role === 'ADMIN' ? 'admin' : 'agent', role }, process.env.JWT_SECRET);
  return fetch(`${base}${path}`, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    ...(body ? { body: JSON.stringify(body) } : {}) });
}

test('all four draws share ₹200; exact limit passes and exceeding is rejected', async () => {
  for (const [id, draw] of ['DEAR 1 PM', 'LSK 3 PM', 'DEAR 6 PM', 'DEAR 8 PM'].entries()) await save(id + 1, 50, draw);
  assert.equal(await usedPaise('agent', new Date()), 20000);
  await assert.rejects(save(5, .01), { code: 'DAILY_AMOUNT_LIMIT' });
  assert.equal(await Booking.countDocuments(), 4);
});
test('two phones cannot spend the same remaining allowance', async () => {
  await save(1, 150);
  const results = await Promise.allSettled([save(2, 40), save(3, 40)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(await usedPaise('agent', new Date()), 19000);
});
test('retries, edits, lowered limits and deleted bills', async () => {
  await save(1, 150);
  await save(1, 150);
  assert.equal(await usedPaise('agent', new Date()), 15000);
  await assert.rejects(save(1, 210), { code: 'DAILY_AMOUNT_LIMIT' });
  await User.updateOne({ username: 'agent' }, { amountLimit: 100 });
  await save(1, 140);
  await Booking.updateOne({ billNo: 1 }, { deletedAt: new Date() });
  await save(2, 100);
  await assert.rejects(save(1, 140), { code: 'DAILY_AMOUNT_LIMIT' });
});
test('new limited booking cannot bypass budget by using yesterday timestamp', async () => {
  await save(1, 200);
  const candidate = doc(2, 20);
  candidate.createdAt = new Date(Date.now() - 86400000);
  await assert.rejects(saveBooking(candidate, { billNo: 2, ownerUsername: 'agent' }), { code: 'DAILY_AMOUNT_LIMIT' });
});
test('Indian midnight, paise and invalid row amounts', () => {
  assert.equal(dayWindow(new Date('2026-10-13T18:29:59Z')).start.toISOString(), '2026-10-12T18:30:00.000Z');
  assert.equal(dayWindow(new Date('2026-10-13T18:30:00Z')).start.toISOString(), '2026-10-13T18:30:00.000Z');
  assert.equal(rowsPaise([{ amount: .1 }, { amount: .2 }]), 30);
  for (const amount of [-1, NaN, Infinity, null]) assert.throws(() => rowsPaise([{ amount }]));
});
test('CUSTOMER limits persist in creation, bulk settings and updates', async () => {
  let response = await request('/api/users', { username: 'customer', password: 'test-only', role: 'CUSTOMER', amountLimit: 200 });
  assert.equal(response.status, 201);
  assert.equal((await response.json()).amountLimit, 200);
  response = await request('/api/settings', { users: [{ username: 'customer', role: 'CUSTOMER', amountLimit: 500 }] });
  assert.equal(response.status, 200);
  assert.equal((await User.findOne({ username: 'customer' })).amountLimit, 500);
  response = await request('/api/users/customer', { amountLimit: -1 }, 'PATCH');
  assert.equal(response.status, 400);
});
test('API uses authenticated user, reports usage and returns a limit error', async () => {
  const candidate = doc(1, 200);
  candidate.username = 'other';
  let response = await request('/api/bookings', candidate, 'POST', 'AGENT');
  assert.equal(response.status, 201);
  assert.equal((await response.json()).username, 'agent');
  response = await request('/api/bookings/daily-limit', null, 'GET', 'AGENT');
  const status = await response.json();
  assert.equal(status.used, 200);
  assert.equal(status.enforced, true);
  response = await request('/api/bookings', doc(2, 1), 'POST', 'AGENT');
  assert.equal(response.status, 409);
  assert.equal((await response.json()).code, 'DAILY_AMOUNT_LIMIT');
});

test('legacy profiles without a limit field return unlimited', async () => {
  await User.collection.updateOne({ username: 'agent' }, { $unset: { amountLimit: '' } });
  const response = await request('/api/bookings/daily-limit', null, 'GET', 'AGENT');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).limit, 0);
});

test('unlimited and administrator accounts retain unrestricted bookings', async () => {
  await User.updateOne({ username: 'agent' }, { amountLimit: 0 });
  await save(1, 1000);
  await User.create({ username: 'admin', passwordHash: 'unused', role: 'ADMIN', amountLimit: 1 });
  const candidate = { ...doc(2, 5000), username: 'admin', ownerUsername: 'admin' };
  await saveBooking(candidate, { billNo: 2, ownerUsername: 'admin' });
  assert.equal(await usedPaise('agent', new Date()), 100000);
  assert.equal(await usedPaise('admin', new Date()), 500000);
});
