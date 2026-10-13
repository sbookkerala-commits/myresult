const mongoose = require('mongoose');
const Booking = require('../models/Booking');
const Result = require('../models/Result');
const Settings = require('../models/Settings');
const Account = require('../models/WalletAccount');
const Entry = require('../models/WalletEntry');
const Winning = require('../models/WalletWinning');
const User = require('../models/User');
const { lockUser } = require('./wallet');
const { LABELS, rowType, dateKey, billDate, drawCutoff, schemesForUser, winningForBill } = require('./winningRules');
let currentRun = null;

async function settleBill(bookingId, resultId) {
  return mongoose.connection.transaction(async session => {
    const bill = await Booking.findById(bookingId).session(session).lean();
    if (!bill) return;
    if (!await User.exists({ username: bill.username, deletedAt: null }).session(session)) return;
    const user = await lockUser(bill.username, session);
    if (user.role === 'ADMIN') return;
    // This write shares the result document with result edits, so stale payouts
    // cannot commit concurrently with a correction or deletion.
    const result = await Result.findOneAndUpdate({ _id: resultId, walletAuthorizedAt: { $ne: null } },
      { $inc: { walletSettlementRevision: 1 } }, { new: true, session }).lean();
    if (!result) return;
    const settings = await Settings.find({ key: { $in: ['priceList', 'drawSchedules'] } }).session(session).lean();
    const priceList = settings.find(s => s.key === 'priceList')?.value;
    const schedules = settings.find(s => s.key === 'drawSchedules')?.value;
    const cutoff = drawCutoff(result.drawCode, result.date, schedules);
    if (new Date() < cutoff) return;
    const filter = { bookingId, drawCode: result.drawCode };
    const existing = await Winning.findOne(filter).session(session);
    const eligible = !result.deletedAt && !bill.deletedAt && billDate(bill) === dateKey(result.date) &&
      new Date(bill.walletAcceptedAt || bill.createdAt) <= cutoff &&
      bill.rows.some(r => rowType(r)?.draw === result.drawCode);
    if (!eligible && !existing) return;
    const schemes = existing?.schemes || schemesForUser(priceList, bill.username);
    const payout = eligible ? winningForBill(bill, result, schemes) : { amountPaise: 0, lines: [] };
    const delta = payout.amountPaise - (existing?.amountPaise || 0);
    const revision = (existing?.revision || 0) + (delta ? 1 : 0);
    const saved = await Winning.findOneAndUpdate(filter, { $set: {
      username: bill.username, resultId, date: result.date, billNo: bill.billNo,
      amountPaise: payout.amountPaise, lines: payout.lines, schemes,
      resultRevision: result.walletResultRevision, revision,
    } }, { session, upsert: true, new: true });
    if (!delta) return saved;
    const account = await Account.findOneAndUpdate({ username: bill.username }, {
      $set: { enabled: true }, $inc: { balancePaise: delta, winningsPaise: delta },
    }, { session, new: true, upsert: true });
    await Entry.create([{
      username: bill.username, kind: delta > 0 ? 'winning' : 'winning_adjustment',
      amountPaise: delta, balanceAfterPaise: account.balancePaise, billNo: bill.billNo,
      winningId: saved._id, drawCode: result.drawCode, businessDate: result.date,
      idempotencyKey: `winning:${saved._id}:${revision}`,
      actor: result.updatedBy,
      note: `${LABELS[result.drawCode]} · ${dateKey(result.date)} · Bill ${bill.billNo} ${delta > 0 ? 'winnings' : 'result correction'}`,
    }], { session });
    return saved;
  });
}

async function settleResult(resultId) {
  const result = await Result.findById(resultId).lean();
  if (!result?.walletAuthorizedAt) return;
  const schedule = await Settings.findOne({ key: 'drawSchedules' }).lean();
  if (new Date() < drawCutoff(result.drawCode, result.date, schedule?.value)) return;
  const start = new Date(`${dateKey(result.date)}T00:00:00Z`);
  const end = new Date(start.getTime() + 86400000);
  const prior = await Winning.find({ resultId }).select('bookingId').lean();
  const cursor = Booking.find({ $or: [
    { rows: { $elemMatch: { type: new RegExp(`^${result.drawCode}-`, 'i') } }, $or: [
      { businessDate: { $gte: start, $lt: end } },
      { businessDate: null, createdAt: { $gte: new Date(start.getTime() - 330 * 60000), $lt: new Date(end.getTime() - 330 * 60000) } },
    ] },
    { _id: { $in: prior.map(w => w.bookingId) } },
  ] }).select('_id').lean().cursor();
  for await (const bill of cursor) await settleBill(bill._id, resultId);
  // A concurrent booking or result edit increases this revision and leaves a
  // durable pending flag for another pass. Crashes likewise leave it pending.
  await Result.updateOne({ _id: resultId, walletResultRevision: result.walletResultRevision }, { $set: { walletPending: false } });
}

function settlePendingWinnings() {
  if (currentRun) return currentRun;
  currentRun = (async () => {
    try {
      const cursor = Result.find({ walletPending: true, walletAuthorizedAt: { $ne: null } }).select('_id').lean().cursor();
      for await (const result of cursor) await settleResult(result._id);
    } catch (error) {
      console.error('Wallet winning settlement pending:', error.code || error.name);
    } finally { currentRun = null; }
  })();
  return currentRun;
}
module.exports = { settleBill, settleResult, settlePendingWinnings };
