const mongoose = require('mongoose');
const User = require('../models/User');
const Booking = require('../models/Booking');
const WalletAccount = require('../models/WalletAccount');
const { applyBooking, snapshot } = require('./wallet');
const { summary: withdrawalSummary } = require('./walletWithdrawals');

const paise = (amount) => Math.round(Number(amount) * 100);

function dayWindow(at) {
  const ist = new Date(at.getTime() + 330 * 60000);
  const start = new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate()) - 330 * 60000);
  return { start, end: new Date(start.getTime() + 86400000) };
}

function rowsPaise(rows) {
  return rows.reduce((total, row) => {
    const amount = Number(row.amount);
    if (row.amount == null || !Number.isFinite(amount) || amount < 0) {
      const error = new Error('Booking amounts must be valid, non-negative amounts');
      error.status = 400;
      throw error;
    }
    return total + paise(amount);
  }, 0);
}

async function usedPaise(username, at, excludeId, session) {
  const { start, end } = dayWindow(at);
  const filter = { username, deletedAt: null, createdAt: { $gte: start, $lt: end } };
  if (excludeId) filter._id = { $ne: excludeId };
  const bills = await Booking.find(filter).select('rows').session(session || null).lean();
  return bills.reduce((total, bill) => total + rowsPaise(bill.rows), 0);
}

async function saveBooking(doc, filter, actorUsername = doc.ownerUsername) {
  const amount = rowsPaise(doc.rows);
  // Updating the same user's document serializes transactions on every server
  // instance, preventing two phones from spending the remaining limit together.
  return mongoose.connection.transaction(async (session) => {
    const user = await User.findOneAndUpdate(
      { username: doc.username, deletedAt: null },
      { $inc: { bookingLimitRevision: 1 } },
      { new: true, session }
    );
    if (!user) {
      const error = new Error('User not found');
      error.status = 404;
      throw error;
    }
    if (user.role !== 'ADMIN' && (user.isBlocked || user.isSalesBlocked)) {
      const error = new Error('Booking is blocked for this user');
      error.status = 403;
      throw error;
    }
    const existing = await Booking.findOne(filter).session(session);
    if (existing) {
      // An edit cannot move a bill into a different date or user's budget.
      doc.createdAt = existing.createdAt;
      doc.username = existing.username;
      doc.ownerUsername = existing.ownerUsername;
    } else if (user.role !== 'ADMIN' && user.amountLimit > 0) {
      doc.createdAt = new Date();
    }
    if (!doc.deletedAt && user.role !== 'ADMIN' && user.amountLimit > 0) {
      const used = await usedPaise(doc.username, doc.createdAt, existing?._id, session);
      const reducing = existing && !existing.deletedAt && amount <= rowsPaise(existing.rows);
      if (!reducing && used + amount > paise(user.amountLimit)) {
        const error = new Error(`Daily booking limit ₹${user.amountLimit} exceeded. Used ₹${used / 100}; this bill ₹${amount / 100}.`);
        error.status = 409;
        error.code = 'DAILY_AMOUNT_LIMIT';
        throw error;
      }
    }
    await applyBooking(doc, existing, user, amount, session, actorUsername);
    const saved = await Booking.findOneAndUpdate(filter, { $set: doc }, { upsert: true, new: true, session });
    const account = await WalletAccount.findOne({ username: user.username }).session(session);
    // Return the balance from the same committed booking transaction. Metadata
    // stays off the booking document and avoids a second client round trip.
    saved.$locals.walletSnapshot = { ...snapshot(account), ...withdrawalSummary(account) };
    saved.$locals.amountLimit = user.amountLimit;
    return saved;
  });
}

module.exports = { dayWindow, rowsPaise, usedPaise, saveBooking };
