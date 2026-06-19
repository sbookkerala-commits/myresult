const Booking = require('../models/Booking');
const Sale = require('../models/Sale');
const Result = require('../models/Result');
const Pending = require('../models/Pending');
const { retentionCutoff } = require('../utils/dates');

async function runRetentionJob() {
  const cutoff = retentionCutoff();
  console.log(`[retention] Purging transactional data before ${cutoff.toISOString()}`);

  const [b1, b2, b3, b4] = await Promise.all([
    Booking.deleteMany({ createdAt: { $lt: cutoff } }),
    Sale.deleteMany({ createdAt: { $lt: cutoff } }),
    Result.deleteMany({ date: { $lt: cutoff } }),
    Pending.deleteMany({ createdAt: { $lt: cutoff } }),
  ]);

  // Hard-delete soft-deleted records older than 7 days
  const softCutoff = new Date();
  softCutoff.setDate(softCutoff.getDate() - 7);
  await Promise.all([
    Booking.deleteMany({ deletedAt: { $ne: null, $lt: softCutoff } }),
    Sale.deleteMany({ deletedAt: { $ne: null, $lt: softCutoff } }),
  ]);

  console.log(
    `[retention] Removed bookings=${b1.deletedCount} sales=${b2.deletedCount} results=${b3.deletedCount} pending=${b4.deletedCount}`
  );
}

module.exports = { runRetentionJob };
