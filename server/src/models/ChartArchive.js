const mongoose = require('mongoose');

/** Permanent chart archive — never auto-deleted */
const chartArchiveSchema = new mongoose.Schema(
  {
    drawCode: { type: String, required: true, index: true },
    date: { type: Date, required: true, index: true },
    drawLabel: { type: String, default: '' },
    prizes: { type: [String], default: [] },
    compliments: { type: [String], default: [] },
    meta: { type: mongoose.Schema.Types.Mixed, default: {} },
    archivedBy: { type: String, default: null },
  },
  { timestamps: true }
);

chartArchiveSchema.index({ drawCode: 1, date: 1 }, { unique: true });

module.exports = mongoose.model('ChartArchive', chartArchiveSchema);
