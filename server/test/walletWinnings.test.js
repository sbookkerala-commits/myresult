const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const express = require('express');
const jwt = require('jsonwebtoken');
const User = require('../src/models/User');
const Booking = require('../src/models/Booking');
const Result = require('../src/models/Result');
const Archive = require('../src/models/ChartArchive');
const Account = require('../src/models/WalletAccount');
const Entry = require('../src/models/WalletEntry');
const Winning = require('../src/models/WalletWinning');
const Settings = require('../src/models/Settings');
const { winningForBill, dateKey } = require('../src/services/winningRules');
const { settleResult, settlePendingWinnings } = require('../src/services/walletWinnings');
const { snapshot } = require('../src/services/wallet');
const { saveBooking } = require('../src/services/dailyBookingLimit');
const day = new Date('2000-01-01T00:00:00Z');
let mongo, server, base;
const models = [User, Booking, Result, Archive, Account, Entry, Winning, Settings];
before(async () => {
  mongo = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  await mongoose.connect(mongo.getUri());
  await Promise.all(models.map(m => m.init()));
  process.env.JWT_SECRET = 'winning-test-only';
  const app = express(); app.use(express.json());
  app.use('/api/results', require('../src/routes/results'));
  app.use('/api/bookings', require('../src/routes/bookings'));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => { await settlePendingWinnings(); await new Promise(resolve => server.close(resolve)); await mongoose.disconnect(); await mongo.stop(); });
beforeEach(async () => {
  await settlePendingWinnings();
  await Promise.all(models.map(m => m.deleteMany({})));
  await User.create([
    { username: 'admin', role: 'ADMIN', passwordHash: 'unused' },
    { username: 'agent', role: 'AGENT', passwordHash: 'unused' },
    { username: 'customer', role: 'CUSTOMER', passwordHash: 'unused' },
  ]);
});
const row = (suffix, number, count = 1, draw = 'DEAR1') => ({ type: `${draw}-${suffix}`, number, count, amount: count * (suffix.length === 1 ? 12 : 10) });
const resultBody = (drawCode = 'DEAR1', prizes = ['123', '456', '789', '246', '802']) => ({ drawCode, date: day, prizes, compliments: ['035'] });
async function result(draw, prizes) { return Result.create({ ...resultBody(draw, prizes), walletAuthorizedAt: new Date(), walletPending: true, walletResultRevision: 1, updatedBy: 'admin' }); }
async function bill(rows = [row('SUPER', '123')], extras = {}) {
  return Booking.create({ billNo: 1, username: 'agent', ownerUsername: 'agent', businessDate: day,
    createdAt: new Date('2000-01-01T06:30:00Z'), walletAcceptedAt: new Date('2000-01-01T06:30:00Z'), rows, ...extras });
}
async function request(path, body, user = 'admin', method = 'POST', role) {
  const token = jwt.sign({ username: user, role: role || (user === 'admin' ? 'ADMIN' : user === 'agent' ? 'AGENT' : 'CUSTOMER') }, process.env.JWT_SECRET);
  return fetch(base + path, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) });
}
async function correction(r, prizes) {
  await Result.updateOne({ _id: r._id }, { prizes, walletPending: true, $inc: { walletResultRevision: 1 } });
  await settleResult(r._id);
}

test('single boards, all two-digit boards, BOX and expanded SET BOX match the existing report', () => {
  const r = resultBody('LSK3', ['011', '006', '944', '234', '720']);
  const rows = [row('A','0',5,'LSK3'), row('B','1',10,'LSK3'), row('C','1',15,'LSK3'),
    row('AB','01',2,'LSK3'), row('BC','11',1,'LSK3'), row('AC','01',1,'LSK3'),
    row('BOX','011',1,'LSK3'), row('BOX','110',1,'LSK3'), row('BOX','006',1,'LSK3'),
    row('SUPER','011',1,'LSK3'), row('SUPER','110',1,'LSK3'), row('SUPER','006',1,'LSK3')];
  const p = winningForBill({ rows }, r);
  assert.equal(p.amountPaise, (3000 + 4*730 + 4130 + 1660 + 5000 + 500)*100);
  assert.equal(p.lines.length, 10);
});
test('five prize tiers and compliments pay once; only first prize qualifies for normal BOX', () => {
  const r = resultBody();
  const p = winningForBill({ rows: ['123','456','789','246','802','035'].map(n => row('SUPER',n,2)) }, r);
  assert.equal(p.amountPaise, (5000+500+250+100+50+20)*2*100);
  assert.equal(winningForBill({rows:[row('BOX','456')]},r).amountPaise,0);
  assert.equal(winningForBill({rows:[row('SUPER','123')]}, { ...r, prizes:['123','123','123'] }).amountPaise,500000);
});
test('configured prize amounts and Super bonuses match the report; 2D uses its fallback bonus', () => {
  const schemes = [{name:'DEAR1-SUPER',rows:[[1,1,5000,400]]}, {name:'DEAR1-A',rows:[[1,1,125,50]]}, {name:'DEAR1-AB',rows:[[1,1,800,0]]}];
  const p = winningForBill({rows:[row('SUPER','123',2),row('A','1'),row('AB','12')]},resultBody(),schemes);
  assert.equal(p.amountPaise, (10800+125+830)*100);
});
test('12000 credit minus 1000 booking plus 5000 winning leaves 16000; concurrent retries never duplicate', async () => {
  await Account.create({username:'agent',enabled:true,balancePaise:1100000,totalCreditPaise:1200000,bookedPaise:100000});
  await bill(); const r=await result();
  await Promise.all([settleResult(r._id),settleResult(r._id)]); await settleResult(r._id);
  const w=snapshot(await Account.findOne({username:'agent'}));
  assert.deepEqual(w,{enabled:true,balance:16000,totalCredit:12000,booked:1000,winnings:5000});
  assert.equal(await Entry.countDocuments({kind:'winning'}),1);
});
test('all four draws credit the booked user; different date, late screenshot-style booking and deleted bills do not win', async () => {
  const codes=['DEAR1','LSK3','DEAR6','DEAR8'];
  await bill(codes.map(c=>row('SUPER','123',1,c)), {username:'customer',ownerUsername:'admin'});
  await bill([row('SUPER','123')],{billNo:2,businessDate:new Date('2000-01-02T00:00:00Z')});
  await bill([row('SUPER','123')],{billNo:3,walletAcceptedAt:new Date('2000-01-01T08:00:00Z')});
  await bill([row('SUPER','123')],{billNo:4,deletedAt:new Date()});
  for(const code of codes) { const r=await result(code); await settleResult(r._id); }
  assert.equal((await Account.findOne({username:'customer'})).balancePaise,2000000);
  assert.equal(await Account.countDocuments({username:'agent'}),0);
  assert.equal(await Account.countDocuments({username:'admin'}),0);
  assert.equal(await Entry.countDocuments({username:'customer'}),4);
});
test('partial results add later prizes without re-paying the first or changing locked prize rates', async () => {
  await bill([row('SUPER','123'),row('SUPER','456')]);
  const r=await result('DEAR1',['123','---','---','---','---']);
  await settleResult(r._id);
  await Settings.create({key:'priceList',value:{agent:[{name:'DEAR1-SUPER',rows:[[1,1,9000,0],[2,1,900,0]]}]}});
  await correction(r,['123','456','---','---','---']); await settleResult(r._id);
  assert.equal((await Account.findOne()).balancePaise,550000);
  assert.equal(await Entry.countDocuments({kind:'winning'}),2);
});
test('result corrections and deletion reverse only the previous payout; spent winnings cannot leave an inflated balance', async () => {
  await bill(); const r=await result(); await settleResult(r._id);
  await Account.updateOne({username:'agent'},{$inc:{balancePaise:-450000,bookedPaise:450000}});
  await correction(r,['456','789','246','802','999']); await settleResult(r._id);
  const w=await Account.findOne(); assert.equal(w.balancePaise,-450000); assert.equal(w.winningsPaise,0);
  assert.equal(await Entry.countDocuments({kind:'winning_adjustment'}),1);
  await correction(r,['123','456','789','246','802']);
  assert.equal((await Account.findOne()).balancePaise,50000);
  await Result.updateOne({_id:r._id},{deletedAt:new Date(),walletPending:true,$inc:{walletResultRevision:1}});
  await settlePendingWinnings(); await settlePendingWinnings();
  assert.equal((await Account.findOne()).balancePaise,-450000);
});
test('customer result sync, including a stale ADMIN JWT role, cannot alter or credit the authoritative result', async () => {
  await bill();
  const reply=await request('/api/results',resultBody(),'customer','POST','ADMIN');
  assert.equal(reply.status,200); assert.equal((await reply.json()).skipped,true);
  assert.equal(await Result.countDocuments(),0); assert.equal(await Entry.countDocuments(),0);
  assert.equal((await request('/api/results/DEAR1/2000-01-01',null,'customer','DELETE','ADMIN')).status,403);
});
test('admin result upload triggers durable automatic winning credit', async () => {
  await bill(); const reply=await request('/api/results',resultBody());
  assert.equal(reply.status,201); await settlePendingWinnings();
  assert.equal((await Account.findOne()).balancePaise,500000);
  assert.equal((await Result.findOne()).walletPending,false);
  assert.equal((await Result.findOne()).date.toISOString(),day.toISOString());
  assert.equal(dateKey('2000-01-01T00:00:00'),'2000-01-01');
  assert.equal(dateKey('2000-02-30T00:00:00'),null);
  assert.equal(dateKey('2000-13-01'),null);
});
test('admin deletion refunds the funded bill and removes its winning exactly once', async () => {
  await Account.create({username:'agent',enabled:true,balancePaise:1100000,totalCreditPaise:1200000,bookedPaise:100000});
  await bill(undefined,{walletTracked:true,walletDebitPaise:100000,walletBasePaise:0});
  const r=await result(); await settleResult(r._id);
  for(let i=0;i<2;i++) { assert.equal((await request('/api/bookings/1',null,'admin','DELETE')).status,200); await settlePendingWinnings(); }
  const w=await Account.findOne(); assert.equal(w.balancePaise,1200000); assert.equal(w.winningsPaise,0); assert.equal(w.bookedPaise,0);
});
test('post-draw customers cannot create a winning bill with a fake earlier time or delete a paid winning', async () => {
  await Account.create({username:'agent',enabled:true,balancePaise:100000});
  const b=await bill(); const r=await result(); await settleResult(r._id);
  assert.equal((await request('/api/bookings/1',null,'agent','DELETE')).status,409);
  await assert.rejects(saveBooking({...b.toObject(),billNo:2}, {billNo:2,ownerUsername:'agent'}),{code:'DRAW_CLOSED'});
  await saveBooking({...b.toObject()}, {billNo:1,ownerUsername:'agent'});
  assert.equal((await Account.findOne()).balancePaise,600000);
});
test('new winning-eligible bookings verify the charged amount against server rates', async () => {
  const future=new Date(Date.now()+2*86400000); future.setUTCHours(0,0,0,0);
  const doc={billNo:3,username:'agent',ownerUsername:'agent',businessDate:future,createdAt:new Date(),rows:[{...row('SUPER','123',50),amount:1}]};
  await assert.rejects(saveBooking(doc,{billNo:3,ownerUsername:'agent'}),{code:'BOOKING_RATE'});
  assert.equal(await Booking.countDocuments(),0);
});
