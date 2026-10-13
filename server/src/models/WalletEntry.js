const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  username: { type: String, required: true, index: true },
  kind: { type: String, enum: ['admin_credit', 'payment', 'booking', 'refund', 'winning', 'winning_adjustment', 'withdrawal_hold', 'withdrawal_release', 'withdrawal_paid'], required: true },
  amountPaise: { type: Number, required: true },
  balanceAfterPaise: { type: Number, required: true },
  actor: String,
  note: String,
  billNo: Number,
  paymentId: mongoose.Schema.Types.ObjectId,
  winningId: mongoose.Schema.Types.ObjectId,
  withdrawalId: mongoose.Schema.Types.ObjectId,
  drawCode: String,
  businessDate: Date,
  idempotencyKey: { type: String, unique: true, sparse: true },
}, { timestamps: true });
schema.index({ username: 1, createdAt: -1 });
module.exports = mongoose.model('WalletEntry', schema);
