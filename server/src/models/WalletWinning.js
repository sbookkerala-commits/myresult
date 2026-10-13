const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  bookingId: { type: mongoose.Schema.Types.ObjectId, required: true },
  resultId: { type: mongoose.Schema.Types.ObjectId, required: true },
  username: { type: String, required: true, index: true },
  drawCode: { type: String, required: true },
  date: { type: Date, required: true },
  billNo: { type: Number, required: true },
  amountPaise: { type: Number, default: 0 },
  resultRevision: { type: Number, default: 0 },
  revision: { type: Number, default: 0 },
  schemes: { type: Array, default: [] },
  lines: { type: Array, default: [] },
}, { timestamps: true });
schema.index({ bookingId: 1, drawCode: 1 }, { unique: true });
module.exports = mongoose.model('WalletWinning', schema);
