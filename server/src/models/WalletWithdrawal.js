const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  username: { type: String, required: true, index: true },
  amountPaise: { type: Number, required: true, min: 1 },
  payeeName: { type: String, required: true },
  destinationType: { type: String, enum: ['upi', 'phone'], required: true },
  destination: { type: String, required: true },
  status: { type: String, enum: ['pending', 'approved', 'paid', 'rejected', 'cancelled'], default: 'pending' },
  idempotencyKey: { type: String, required: true, unique: true },
  approvedBy: String,
  approvedAt: Date,
  reviewedBy: String,
  reviewedAt: Date,
  reviewNote: String,
  transferReference: { type: String, unique: true, sparse: true },
  paidAt: Date,
}, { timestamps: true });
schema.index({ status: 1, createdAt: 1 });
module.exports = mongoose.model('WalletWithdrawal', schema);
