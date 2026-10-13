const mongoose = require('mongoose');
const User = require('../models/User');
const WalletAccount = require('../models/WalletAccount');
const WalletEntry = require('../models/WalletEntry');
const WalletPayment = require('../models/WalletPayment');
const Settings = require('../models/Settings');
const Result = require('../models/Result');
const Winning = require('../models/WalletWinning');
const { rowType, billDate, drawCutoff, saleAmount } = require('./winningRules');

function error(message, status = 400, code) {
  return Object.assign(new Error(message), { status, code });
}
function money(value, minimum = 0) {
  if (value == null || typeof value === 'boolean' || `${value}`.trim() === '') throw error('Enter a valid amount');
  const amount = Number(value);
  const result = Math.round(amount * 100);
  if (!Number.isFinite(amount) || !Number.isSafeInteger(result) || result < minimum || Math.abs(amount * 100 - result) > .000001) {
    throw error(`Enter a valid amount${minimum ? ` of at least ₹${minimum / 100}` : ''} (maximum two decimal places)`);
  }
  return result;
}
async function lockUser(username, session) {
  const user = await User.findOneAndUpdate({ username, deletedAt: null },
    { $inc: { bookingLimitRevision: 1 } }, { new: true, session });
  if (!user) throw error('User not found', 404);
  return user;
}
function snapshot(account) {
  return {
    enabled: !!account?.enabled,
    balance: (account?.balancePaise || 0) / 100,
    totalCredit: (account?.totalCreditPaise || 0) / 100,
    winnings: (account?.winningsPaise || 0) / 100,
    booked: (account?.bookedPaise || 0) / 100,
  };
}
async function credit(username, amountPaise, actor, kind, note, idempotencyKey, session, paymentId) {
  const existing = await WalletEntry.findOne({ idempotencyKey }).session(session).lean();
  if (existing) {
    if (existing.username !== username || existing.amountPaise !== amountPaise || existing.kind !== kind) {
      throw error('This credit reference was already used', 409);
    }
    return WalletAccount.findOne({ username }).session(session);
  }
  const account = await WalletAccount.findOneAndUpdate({ username }, {
    $set: { enabled: true },
    $inc: { balancePaise: amountPaise, totalCreditPaise: amountPaise },
  }, { upsert: true, new: true, session });
  await WalletEntry.create([{ username, amountPaise, kind, actor, note,
    balanceAfterPaise: account.balancePaise, idempotencyKey, paymentId }], { session });
  return account;
}
async function adminCredit(username, amount, actor, requestKey) {
  const amountPaise = money(amount, 1);
  return mongoose.connection.transaction(async session => {
    const user = await lockUser(username, session);
    if (user.role === 'ADMIN') throw error('Select a customer or agent wallet');
    return credit(username, amountPaise, actor, 'admin_credit', 'Credit added by admin',
      `admin:${actor}:${requestKey}`, session);
  });
}
async function reviewPayment(id, actor, action, note) {
  if (!mongoose.isValidObjectId(id)) throw error('Invalid payment', 400);
  if (!['approved', 'rejected'].includes(action)) throw error('Choose approve or reject');
  if (action === 'rejected' && !note?.trim()) throw error('Enter a reason for rejection');
  return mongoose.connection.transaction(async session => {
    const payment = await WalletPayment.findById(id).session(session);
    if (!payment) throw error('Payment not found', 404);
    await lockUser(payment.username, session);
    if (payment.status !== 'pending') {
      if (payment.status === action) return payment;
      throw error('This payment was already reviewed', 409);
    }
    payment.status = action;
    payment.reviewedBy = actor;
    payment.reviewedAt = new Date();
    payment.reviewNote = note?.trim() || '';
    await payment.save({ session });
    if (action === 'approved') {
      await credit(payment.username, payment.amountPaise, actor, 'payment', `UPI ${payment.utr}`,
        `payment:${payment._id}`, session, payment._id);
    }
    return payment;
  });
}
async function applyBooking(doc, existing, user, amountPaise, session, actorUsername = doc.ownerUsername) {
  const account = await WalletAccount.findOne({ username: user.username }).session(session);
  if (user.role === 'ADMIN') return;
  const settings = Object.fromEntries((await Settings.find({ key: { $in: ['priceList', 'priceListGameRates', 'rateSets', 'drawSchedules'] } })
    .session(session).lean()).map(s => [s.key, s.value]));
  const owner = actorUsername === user.username ? user : await User.findOne({ username: actorUsername, deletedAt: null }).session(session);
  const unchanged = existing && JSON.stringify(existing.rows) === JSON.stringify(doc.rows) &&
    billDate(existing) === billDate(doc) && !!existing.deletedAt === !!doc.deletedAt;
  const now = new Date();
  const draws = [...new Set(doc.rows.map(rowType).filter(Boolean).map(t => t.draw))];
  if (owner?.role !== 'ADMIN' && !unchanged) {
    for (const draw of new Set([...draws, ...(existing?.rows || []).map(rowType).filter(Boolean).map(t => t.draw)])) {
      const day = billDate(existing || doc);
      const known = await Result.exists({ drawCode: draw, date: new Date(`${day}T00:00:00Z`), walletAuthorizedAt: { $ne: null }, deletedAt: null }).session(session);
      if (now >= drawCutoff(draw, day, settings.drawSchedules) || known) {
        throw error('This draw is closed. Select the next draw date.', 409, 'DRAW_CLOSED');
      }
    }
  }
  if (!doc.deletedAt && !unchanged) {
    for (const row of doc.rows) {
      if (!rowType(row)) continue;
      const count = Number(row.count);
      if (!Number.isSafeInteger(count) || count <= 0 || Math.abs(Math.round(Number(row.amount) * 100) - saleAmount(row, user, settings)) > 1) {
        throw error('Booking count or amount does not match this user\'s rate. Refresh and try again.', 409, 'BOOKING_RATE');
      }
    }
  }
  doc.walletAcceptedAt = existing?.walletAcceptedAt || existing?.createdAt || now;
  const previous = existing ? await Winning.find({ bookingId: existing._id }).select('resultId').session(session).lean() : [];
  const days = [...new Set([billDate(doc), ...(existing ? [billDate(existing)] : [])])].map(day => new Date(`${day}T00:00:00Z`));
  const oldDraws = (existing?.rows || []).map(rowType).filter(Boolean).map(t => t.draw);
  await Result.updateMany({ walletAuthorizedAt: { $ne: null }, $or: [
    { date: { $in: days }, drawCode: { $in: [...draws, ...oldDraws] } },
    { _id: { $in: previous.map(w => w.resultId) } },
  ] }, { $set: { walletPending: true }, $inc: { walletResultRevision: 1 } }, { session });
  if (!account?.enabled) return;
  const oldDebit = existing?.walletDebitPaise || 0;
  const oldBase = existing?.walletTracked ? (existing.walletBasePaise || 0) :
    (existing ? existing.rows.reduce((sum, row) => sum + Math.round(Number(row.amount) * 100), 0) : 0);
  const debit = doc.deletedAt ? 0 : Math.max(0, amountPaise - oldBase);
  const difference = debit - oldDebit;
  if (difference > 0 && difference > account.balancePaise) {
    throw error(`Insufficient wallet balance. Available ₹${(account.balancePaise / 100).toFixed(2)}.`, 409, 'WALLET_BALANCE');
  }
  if (difference) {
    account.balancePaise -= difference;
    account.bookedPaise += difference;
    await account.save({ session });
    await WalletEntry.create([{ username: user.username, kind: difference > 0 ? 'booking' : 'refund',
      amountPaise: -difference, balanceAfterPaise: account.balancePaise, billNo: doc.billNo,
      note: `Bill ${doc.billNo}`, actor: doc.ownerUsername }], { session });
  }
  doc.walletTracked = true;
  doc.walletBasePaise = oldBase;
  doc.walletDebitPaise = debit;
}
module.exports = { error, money, lockUser, snapshot, adminCredit, reviewPayment, applyBooking };
