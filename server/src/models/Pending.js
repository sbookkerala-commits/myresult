const mongoose = require('mongoose');

/** Pending / draft bookings — 20-day rolling retention */
const pendingSchema = new mongoose.Schema(
  {
    ownerUsername: { type: String, required: true, index: true },
    payload: { type: mongoose.Schema.Types.Mixed, required: true },
    createdAt: { type: Date, default: Date.now, index: true },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

pendingSchema.index({ deletedAt: 1, createdAt: 1 });

module.exports = mongoose.model('Pending', pendingSchema);
