const mongoose = require('mongoose');

const bookingSchema = new mongoose.Schema(
  {
    billNo: { type: Number, required: true },
    username: { type: String, required: true, index: true },
    ownerUsername: { type: String, required: true, index: true },
    rows: { type: Array, default: [] },
    drawName: { type: String, default: '' },
    customerName: { type: String, default: '' },
    businessDate: { type: Date, default: null, index: true },
    createdAt: { type: Date, required: true, index: true },
    deletedAt: { type: Date, default: null },
    clientId: { type: String, default: null },
  },
  { timestamps: true }
);

bookingSchema.index({ billNo: 1, ownerUsername: 1 }, { unique: true });
bookingSchema.index({ deletedAt: 1, createdAt: 1 });

module.exports = mongoose.model('Booking', bookingSchema);
