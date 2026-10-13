const Booking = require('../models/Booking');
const Sale = require('../models/Sale');
const Result = require('../models/Result');
const ChartArchive = require('../models/ChartArchive');
const Settings = require('../models/Settings');
const User = require('../models/User');
const WalletAccount = require('../models/WalletAccount');
const WalletEntry = require('../models/WalletEntry');
const WalletPayment = require('../models/WalletPayment');
const WalletWinning = require('../models/WalletWinning');
const WalletWithdrawal = require('../models/WalletWithdrawal');
const BackupSnapshot = require('../models/BackupSnapshot');
const { retentionCutoff } = require('../utils/dates');
const {
  BACKUP_BATCH_SIZE,
  BACKUP_MAX_DOCS,
} = require('../utils/queryLimits');
const { logInfo, logWarn, logError, logMemory } = require('../utils/logger');

function isCloudDatabase() {
  return (
    process.env.USE_EMBEDDED_MONGO !== 'true' &&
    process.env.USE_EMBEDDED_MONGO !== '1' &&
    !!process.env.MONGODB_URI
  );
}

/** Load documents in batches to avoid loading entire collections into RAM. */
async function loadInBatches(Model, filter, { limit = BACKUP_MAX_DOCS, select } = {}) {
  const out = [];
  let skip = 0;
  while (out.length < limit) {
    const batchSize = Math.min(BACKUP_BATCH_SIZE, limit - out.length);
    let q = Model.find(filter).sort({ _id: 1 }).skip(skip).limit(batchSize);
    if (select) q = q.select(select);
    const batch = await q.lean();
    if (!batch.length) break;
    out.push(...batch);
    skip += batch.length;
    if (batch.length < batchSize) break;
  }
  return out;
}

async function runDailyBackup() {
  const cutoff = retentionCutoff();
  const stamp = new Date().toISOString().slice(0, 10);
  logInfo(`[backup] Starting daily backup ${stamp}`);
  logMemory('memory before backup');

  try {
    const [bookings, sales, results, chartArchive, settings, users, walletAccounts, walletEntries, walletPayments, walletWinnings, walletWithdrawals] =
      await Promise.all([
        loadInBatches(
          Booking,
          { createdAt: { $gte: cutoff }, deletedAt: null },
          { limit: BACKUP_MAX_DOCS }
        ),
        loadInBatches(
          Sale,
          { createdAt: { $gte: cutoff }, deletedAt: null },
          { limit: BACKUP_MAX_DOCS }
        ),
        loadInBatches(
          Result,
          { date: { $gte: cutoff }, deletedAt: null },
          { limit: Math.min(BACKUP_MAX_DOCS, 2000) }
        ),
        loadInBatches(ChartArchive, {}, { limit: 1000 }),
        Settings.find().lean(),
        User.find({ deletedAt: null })
          .select('username role isBlocked')
          .lean(),
        loadInBatches(WalletAccount, {}),
        loadInBatches(WalletEntry, {}, { limit: 5000 }),
        loadInBatches(WalletPayment, {}, { limit: 5000 }),
        loadInBatches(WalletWinning, {}, { limit: 5000 }),
        loadInBatches(WalletWithdrawal, {}, { limit: 5000 }),
      ]);

    const counts = {
      bookings: bookings.length,
      sales: sales.length,
      results: results.length,
      chartArchive: chartArchive.length,
      settings: settings.length,
      users: users.length,
      walletAccounts: walletAccounts.length,
      walletEntries: walletEntries.length,
      walletPayments: walletPayments.length,
      walletWinnings: walletWinnings.length,
      walletWithdrawals: walletWithdrawals.length,
    };
    logInfo('[backup] Loaded collections', counts);

    // Store a compact metadata snapshot + capped payloads to stay under BSON 16MB
    // and avoid OOM. Full dumps are truncated intentionally on small Render plans.
    const payload = {
      exportedAt: new Date().toISOString(),
      retentionFrom: cutoff,
      truncated: {
        bookings: bookings.length >= BACKUP_MAX_DOCS,
        sales: sales.length >= BACKUP_MAX_DOCS,
        chartArchive: chartArchive.length >= 1000,
      },
      counts,
      bookings,
      sales,
      results,
      chartArchive,
      settings,
      users,
      walletAccounts,
      walletEntries,
      walletPayments,
      walletWinnings,
      walletWithdrawals,
    };

    const approxBytes = Buffer.byteLength(JSON.stringify(payload), 'utf8');
    const approxMb = Math.round((approxBytes / 1024 / 1024) * 10) / 10;
    logInfo(`[backup] Payload size ~${approxMb} MB`);

    // MongoDB BSON document limit is 16MB — refuse oversized cloud snapshots
    const BSON_SOFT_LIMIT = 14 * 1024 * 1024;
    if (isCloudDatabase() && approxBytes > BSON_SOFT_LIMIT) {
      logWarn(
        '[backup] Payload too large for single MongoDB document; storing summary only'
      );
      const summaryPayload = {
        exportedAt: payload.exportedAt,
        retentionFrom: cutoff,
        counts,
        truncated: true,
        reason: 'payload_exceeded_bson_soft_limit',
        approxMb,
      };
      await BackupSnapshot.findOneAndUpdate(
        { dateKey: stamp },
        {
          exportedAt: new Date(),
          retentionFrom: cutoff,
          payload: summaryPayload,
        },
        { upsert: true, new: true }
      );
      logMemory('memory after backup (summary)');
      return `mongodb://backup-${stamp}-summary`;
    }

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
      logInfo(`[backup] Stored cloud snapshot backup-${stamp} in MongoDB`);
      logMemory('memory after backup');
      return `mongodb://backup-${stamp}`;
    }

    const fs = require('fs');
    const path = require('path');
    const dir = process.env.BACKUP_DIR || './backups';
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, `backup-${stamp}.json`);
    fs.writeFileSync(file, JSON.stringify(payload));
    logInfo(`[backup] Written ${file}`);
    logMemory('memory after backup');
    return file;
  } catch (err) {
    logError('[backup] Failed', err);
    throw err;
  }
}

module.exports = { runDailyBackup };
