const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  username: { type: String, required: true, index: true },
  amountPaise: { type: Number, required: true, min: 20000 },
  utr: { type: String, required: true, unique: true },
  idempotencyKey: { type: String, required: true },
  receipt: { type: String, required: function () { return this.source !== 'whatsapp'; }, select: false },
  receiptHash: { type: String, unique: true, sparse: true, select: false },
  source: { type: String, enum: ['app', 'whatsapp'], default: 'app' },
  submittedBy: String,
  utrIsGenerated: { type: Boolean, default: false },
  status: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending', index: true },
  reviewedBy: String,
  reviewedAt: Date,
  reviewNote: String,
}, { timestamps: true });
schema.index({ username: 1, idempotencyKey: 1 }, { unique: true });
schema.index({ status: 1, createdAt: -1 });
module.exports = mongoose.model('WalletPayment', schema);
