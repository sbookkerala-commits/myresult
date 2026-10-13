const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  enabled: { type: Boolean, default: false },
  balancePaise: { type: Number, default: 0 },
  totalCreditPaise: { type: Number, default: 0, min: 0 },
  winningsPaise: { type: Number, default: 0, min: 0 },
  bookedPaise: { type: Number, default: 0, min: 0 },
}, { timestamps: true });
module.exports = mongoose.model('WalletAccount', schema);
