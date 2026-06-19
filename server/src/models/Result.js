const mongoose = require('mongoose');

const resultSchema = new mongoose.Schema(
  {
    drawCode: { type: String, required: true, index: true },
    date: { type: Date, required: true, index: true },
    prizes: { type: [String], default: [] },
    compliments: { type: [String], default: [] },
    updatedBy: { type: String, default: null },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

resultSchema.index({ drawCode: 1, date: 1 }, { unique: true });
resultSchema.index({ deletedAt: 1, date: 1 });

module.exports = mongoose.model('Result', resultSchema);
