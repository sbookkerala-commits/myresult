const mongoose = require('mongoose');

const backupSnapshotSchema = new mongoose.Schema(
  {
    dateKey: { type: String, required: true, unique: true },
    exportedAt: { type: Date, required: true },
    retentionFrom: { type: Date },
    payload: { type: mongoose.Schema.Types.Mixed, required: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model('BackupSnapshot', backupSnapshotSchema);
