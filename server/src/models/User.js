const mongoose = require('mongoose');

const userSchema = new mongoose.Schema(
  {
    username: { type: String, required: true, unique: true, trim: true, lowercase: true },
    passwordHash: { type: String, required: true },
    role: {
      type: String,
      enum: ['ADMIN', 'AGENT', 'SUBAGENT', 'CUSTOMER'],
      required: true,
    },
    isBlocked: { type: Boolean, default: false },
    deletedAt: { type: Date, default: null },
    createdBy: { type: String, default: null },
  },
  { timestamps: true }
);

userSchema.index({ deletedAt: 1 });

module.exports = mongoose.model('User', userSchema);
