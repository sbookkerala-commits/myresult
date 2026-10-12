const mongoose = require('mongoose');
module.exports = mongoose.model('NotificationDevice', new mongoose.Schema({
  token: { type: String, required: true, unique: true, select: false },
  username: { type: String, required: true, index: true },
}, { timestamps: true }));
