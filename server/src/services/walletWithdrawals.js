const mongoose = require('mongoose');
const Withdrawal = require('../models/WalletWithdrawal');
const Account = require('../models/WalletAccount');
const Entry = require('../models/WalletEntry');
const { error, money, lockUser } = require('./wallet');

function payoutDetails(body) {
  const payeeName = typeof body.payeeName === 'string' ? body.payeeName.trim() : '';
  const destinationType = body.destinationType;
  const destination = typeof body.destination === 'string' ? body.destination.trim().toLowerCase() : '';
  if (!payeeName || payeeName.length > 80 || /[\r\n\x00-\x1f]/.test(payeeName)) throw error('Enter the recipient name (maximum 80 characters)');
  if (destinationType === 'upi' ? !/^[a-z0-9._-]{2,100}@[a-z0-9.-]{2,50}$/.test(destination) :
      destinationType !== 'phone' || !/^[6-9]\d{9}$/.test(destination)) {
    throw error('Enter a valid UPI ID or 10-digit Google Pay phone number');
  }
  return { payeeName, destinationType, destination };
}
function summary(account) {
  return {
    withdrawable: Math.max(0, account?.balancePaise || 0) / 100,
    withdrawalReserved: (account?.withdrawalReservedPaise || 0) / 100,
    withdrawn: (account?.withdrawnPaise || 0) / 100,
  };
}
async function requestWithdrawal(username, body, requestKey) {
  if (!['string', 'number'].includes(typeof body.amount)) throw error('Enter a valid withdrawal amount');
  const amountPaise = money(body.amount, 1);
  const details = payoutDetails(body);
  const idempotencyKey = `withdrawal:${username}:${requestKey}`;
  return mongoose.connection.transaction(async session => {
    const user = await lockUser(username, session);
    if (user.role === 'ADMIN' || user.isBlocked) throw error('Use an active customer or agent wallet', 403);
    const previous = await Withdrawal.findOne({ idempotencyKey }).session(session);
    if (previous) {
      if (previous.amountPaise !== amountPaise || Object.keys(details).some(k => previous[k] !== details[k])) {
        throw error('This withdrawal reference was already used with different details', 409);
      }
      return previous;
    }
    const account = await Account.findOneAndUpdate({ username, enabled: true, balancePaise: { $gte: amountPaise } }, {
      $inc: { balancePaise: -amountPaise, withdrawalReservedPaise: amountPaise },
    }, { session, new: true });
    if (!account) throw error('Withdrawal exceeds the available wallet balance', 409, 'WALLET_BALANCE');
    const [withdrawal] = await Withdrawal.create([{ username, amountPaise, ...details, idempotencyKey }], { session });
    await Entry.create([{ username, kind: 'withdrawal_hold', amountPaise: -amountPaise,
      balanceAfterPaise: account.balancePaise, actor: username, withdrawalId: withdrawal._id,
      note: 'Withdrawal requested', idempotencyKey: `withdrawal-hold:${withdrawal._id}` }], { session });
    return withdrawal;
  });
}
async function reviewWithdrawal(id, actor, body, { customer = false } = {}) {
  if (!mongoose.isValidObjectId(id)) throw error('Invalid withdrawal');
  const action = body.action;
  if (!(customer ? ['cancelled'] : ['approved', 'paid', 'rejected']).includes(action)) throw error('Choose a valid withdrawal action');
  const note = typeof body.note === 'string' ? body.note.trim() : '';
  if (note.length > 300 || (action === 'rejected' && !note)) throw error('Enter a rejection reason (maximum 300 characters)');
  const reference = typeof body.transferReference === 'string' ? body.transferReference.replace(/\s/g, '').toUpperCase() : '';
  if (action === 'paid' && (!/^[A-Z0-9_-]{6,80}$/.test(reference) || body.confirmed !== true)) {
    throw error('Confirm that money has been sent and enter its transaction reference');
  }
  try {
    return await mongoose.connection.transaction(async session => {
      const withdrawal = await Withdrawal.findById(id).session(session);
      if (!withdrawal) throw error('Withdrawal not found', 404);
      if (customer && withdrawal.username !== actor) throw error('Withdrawal not found', 404);
      await lockUser(withdrawal.username, session);
      if (withdrawal.status === action) {
        if (action === 'paid' && withdrawal.transferReference !== reference) throw error('This withdrawal already has a different payment reference', 409);
        if (action === 'approved' && withdrawal.approvedBy !== actor) throw error('Another admin is handling this withdrawal', 409);
        return withdrawal;
      }
      if (!['pending', 'approved'].includes(withdrawal.status)) throw error('This withdrawal is already completed', 409);
      if (customer && withdrawal.status !== 'pending') throw error('The admin is processing this withdrawal; contact the admin', 409);
      if (!customer && withdrawal.status === 'approved' && withdrawal.approvedBy !== actor) {
        throw error('Only the admin handling this withdrawal can complete or reject it', 409);
      }
      if (action === 'paid' && withdrawal.status !== 'approved') throw error('Approve this withdrawal before transferring money', 409);
      const account = await Account.findOne({ username: withdrawal.username }).session(session);
      if (!account || (account.withdrawalReservedPaise || 0) < withdrawal.amountPaise) throw error('Withdrawal reservation is unavailable; contact support', 409);
      if (['approved', 'paid'].includes(action) && account.balancePaise < 0) {
        throw error('A wallet correction must be resolved before this withdrawal can be paid', 409);
      }
      withdrawal.status = action;
      if (action === 'approved') {
        withdrawal.approvedBy = actor;
        withdrawal.approvedAt = new Date();
      } else {
        account.withdrawalReservedPaise -= withdrawal.amountPaise;
        const paid = action === 'paid';
        if (paid) {
          account.withdrawnPaise = (account.withdrawnPaise || 0) + withdrawal.amountPaise;
          withdrawal.transferReference = reference;
          withdrawal.paidAt = new Date();
        } else account.balancePaise += withdrawal.amountPaise;
        await account.save({ session });
        await Entry.create([{ username: withdrawal.username, kind: paid ? 'withdrawal_paid' : 'withdrawal_release',
          amountPaise: paid ? 0 : withdrawal.amountPaise, balanceAfterPaise: account.balancePaise,
          actor, withdrawalId: withdrawal._id,
          note: paid ? `Withdrawal paid · ${reference}` : `Withdrawal ${action} · ${note || 'Cancelled by customer'}`,
          idempotencyKey: `withdrawal-final:${withdrawal._id}` }], { session });
        withdrawal.reviewedBy = actor;
        withdrawal.reviewedAt = new Date();
        withdrawal.reviewNote = note;
      }
      await withdrawal.save({ session });
      return withdrawal;
    });
  } catch (e) {
    if (e.code === 11000) throw error('This payment transaction reference has already been recorded', 409);
    throw e;
  }
}
module.exports = { payoutDetails, summary, requestWithdrawal, reviewWithdrawal };
