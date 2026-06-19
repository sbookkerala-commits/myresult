const fs = require('fs');
const path = require('path');
const Booking = require('../models/Booking');
const Sale = require('../models/Sale');
const Result = require('../models/Result');
const ChartArchive = require('../models/ChartArchive');
const Settings = require('../models/Settings');
const User = require('../models/User');
const BackupSnapshot = require('../models/BackupSnapshot');
const { retentionCutoff } = require('../utils/dates');

function isCloudDatabase() {
  return (
    process.env.USE_EMBEDDED_MONGO !== 'true' &&
    process.env.USE_EMBEDDED_MONGO !== '1' &&
    !!process.env.MONGODB_URI
  );
}

async function runDailyBackup() {
  const cutoff = retentionCutoff();
  const stamp = new Date().toISOString().slice(0, 10);

  const [bookings, sales, results, chartArchive, settings, users] =
    await Promise.all([
      Booking.find({ createdAt: { $gte: cutoff }, deletedAt: null }).lean(),
      Sale.find({ createdAt: { $gte: cutoff }, deletedAt: null }).lean(),
      Result.find({ date: { $gte: cutoff }, deletedAt: null }).lean(),
      ChartArchive.find().sort({ date: -1 }).limit(5000).lean(),
      Settings.find().lean(),
      User.find({ deletedAt: null }).select('username role isBlocked').lean(),
    ]);

  const payload = {
    exportedAt: new Date().toISOString(),
    retentionFrom: cutoff,
    bookings,
    sales,
    results,
    chartArchive,
    settings,
    users,
  };

  if (isCloudDatabase()) {
    await BackupSnapshot.findOneAndUpdate(
      { dateKey: stamp },
      {
        exportedAt: new Date(),
        retentionFrom: cutoff,
        payload,
      },
      { upsert: true, new: true }
    );
    console.log(`[backup] Stored cloud snapshot backup-${stamp} in MongoDB`);
    return `mongodb://backup-${stamp}`;
  }

  const dir = process.env.BACKUP_DIR || './backups';
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `backup-${stamp}.json`);
  fs.writeFileSync(file, JSON.stringify(payload, null, 2));
  console.log(`[backup] Written ${file}`);
  return file;
}

module.exports = { runDailyBackup };
