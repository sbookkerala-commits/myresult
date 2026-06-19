const mongoose = require('mongoose');

const saleSchema = new mongoose.Schema(
  {
    type: { type: String, required: true },
    number: { type: String, required: true },
    count: { type: Number, required: true },
    amount: { type: Number, required: true },
    time: { type: String, default: '' },
    username: { type: String, required: true, index: true },
    ownerUsername: { type: String, required: true, index: true },
    createdAt: { type: Date, required: true, index: true },
    deletedAt: { type: Date, default: null },
    clientId: { type: String, default: null },
  },
  { timestamps: true }
);

saleSchema.index({ deletedAt: 1, createdAt: 1 });

module.exports = mongoose.model('Sale', saleSchema);
