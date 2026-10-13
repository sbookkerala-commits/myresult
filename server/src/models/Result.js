const mongoose = require('mongoose');

const resultSchema = new mongoose.Schema(
  {
    drawCode: { type: String, required: true, index: true },
    date: { type: Date, required: true, index: true },
    prizes: { type: [String], default: [] },
    compliments: { type: [String], default: [] },
    manualOverride: { type: Boolean, default: false },
    updatedBy: { type: String, default: null },
    deletedAt: { type: Date, default: null },
    walletAuthorizedAt: { type: Date, default: null },
    walletResultRevision: { type: Number, default: 0 },
    walletSettlementRevision: { type: Number, default: 0 },
    walletPending: { type: Boolean, default: false },
  },
  { timestamps: true }
);

resultSchema.index({ drawCode: 1, date: 1 }, { unique: true });
resultSchema.index({ deletedAt: 1, date: 1 });

module.exports = mongoose.model('Result', resultSchema);
