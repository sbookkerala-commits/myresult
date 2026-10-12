const mongoose = require('mongoose');
module.exports = mongoose.model('NotificationCredential', new mongoose.Schema({
  name: { type: String, unique: true, required: true },
  encrypted: { type: String, required: true, select: false },
  projectId: String,
  updatedBy: String,
}, { timestamps: true }));
