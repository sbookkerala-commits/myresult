const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  withdrawalId: { type: mongoose.Schema.Types.ObjectId, required: true },
  deviceId: { type: mongoose.Schema.Types.ObjectId, required: true },
  sentAt: Date,
  nextAttemptAt: { type: Date, default: Date.now },
  leaseUntil: Date,
  attempts: { type: Number, default: 0 },
  lastError: String,
}, { timestamps: true });
schema.index({ withdrawalId: 1, deviceId: 1 }, { unique: true });
module.exports = mongoose.model('WithdrawalPushDelivery', schema);
