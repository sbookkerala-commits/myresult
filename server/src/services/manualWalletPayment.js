const crypto = require('crypto');
const mongoose = require('mongoose');
const Payment = require('../models/WalletPayment');
const Account = require('../models/WalletAccount');
const { error, money, lockUser, credit, snapshot } = require('./wallet');

const receiptFingerprint = image => image
  ? crypto.createHash('sha256').update(Buffer.from(image.split(',')[1], 'base64')).digest('hex')
  : undefined;

async function verifiedWhatsAppPayment({ username, amount, actor, requestKey, utr, receipt, note = '' }) {
  const amountPaise = money(amount, 20000);
  const idempotencyKey = `manual:${actor}:${requestKey}`;
  const reference = utr || `MANUAL${crypto.createHash('sha256').update(idempotencyKey).digest('hex').slice(0, 24).toUpperCase()}`;
  const receiptHash = receiptFingerprint(receipt);
  if (!utr && !receipt) throw error('Enter a UTR or attach the payment screenshot');

  // A unique-reference collision across two different wallets can occur outside
  // the per-user lock; retry after rollback to return the existing reference.
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      return await mongoose.connection.transaction(async session => {
        const user = await lockUser(username, session);
        if (user.role === 'ADMIN') throw error('Select a customer or agent wallet');
        const matches = await Payment.find({ $or: [
          { utr: reference }, { idempotencyKey },
          ...(receiptHash ? [{ receiptHash }, { receipt }] : []),
        ] }).session(session).select('+receiptHash');
        if (matches.length > 1) throw error('The UTR and screenshot refer to different payments', 409);
        let payment = matches[0];
        if (payment) {
          if (payment.username !== username || payment.amountPaise !== amountPaise ||
              (utr && payment.utr !== reference) ||
              (payment.idempotencyKey === idempotencyKey &&
                (payment.utr !== reference || (!utr && payment.receiptHash !== receiptHash)))) {
            throw error('This payment reference was already used with different details', 409);
          }
          if (payment.status === 'rejected') throw error('This payment was previously rejected', 409);
          if (payment.status === 'approved') {
            const account = await Account.findOne({ username }).session(session);
            return { ...snapshot(account), paymentId: payment._id, alreadyCredited: true };
          }
        } else {
          [payment] = await Payment.create([{
            username, amountPaise, utr: reference, utrIsGenerated: !utr,
            receipt, receiptHash, idempotencyKey, source: 'whatsapp', submittedBy: actor,
          }], { session });
        }
        payment.status = 'approved';
        payment.reviewedBy = actor;
        payment.reviewedAt = new Date();
        payment.reviewNote = note || 'Verified from WhatsApp';
        await payment.save({ session });
        const description = `WhatsApp payment${utr ? ` · UTR ${utr}` : ''}${note ? ` · ${note}` : ''}`;
        const account = await credit(username, amountPaise, actor, 'payment', description,
          `payment:${payment._id}`, session, payment._id);
        return { ...snapshot(account), paymentId: payment._id, alreadyCredited: false };
      });
    } catch (e) {
      if (e.code !== 11000 || attempt === 1) throw e;
    }
  }
}

module.exports = { verifiedWhatsAppPayment, receiptFingerprint };
