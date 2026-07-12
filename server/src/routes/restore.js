const express = require('express');
const Booking = require('../models/Booking');
const Sale = require('../models/Sale');
const Result = require('../models/Result');
const Pending = require('../models/Pending');
const ChartArchive = require('../models/ChartArchive');
const Settings = require('../models/Settings');
const User = require('../models/User');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');
const {
  RESTORE_BOOKING_LIMIT,
  RESTORE_SALE_LIMIT,
  RESTORE_CHART_LIMIT,
} = require('../utils/queryLimits');
const { logInfo, logError, logMemory } = require('../utils/logger');

const router = express.Router();

/** Login restore — cloud → local SQLite on device (capped to prevent OOM) */
router.get('/restore', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const owner =
      req.user.role === 'ADMIN' ? {} : { ownerUsername: req.user.username };

    logInfo(`[restore] start user=${req.user.username} role=${req.user.role}`);
    logMemory('memory before restore');

    const [bookings, sales, results, pending, chartArchive, settingsDocs, profileUser] =
      await Promise.all([
        Booking.find({ deletedAt: null, createdAt: { $gte: cutoff }, ...owner })
          .sort({ createdAt: -1 })
          .limit(RESTORE_BOOKING_LIMIT)
          .lean(),
        Sale.find({ deletedAt: null, createdAt: { $gte: cutoff }, ...owner })
          .sort({ createdAt: -1 })
          .limit(RESTORE_SALE_LIMIT)
          .lean(),
        Result.find({ deletedAt: null, date: { $gte: cutoff } })
          .sort({ date: -1 })
          .limit(2000)
          .lean(),
        Pending.find({
          deletedAt: null,
          createdAt: { $gte: cutoff },
          ownerUsername: req.user.username,
        })
          .sort({ createdAt: -1 })
          .limit(1000)
          .lean(),
        ChartArchive.find().sort({ date: -1 }).limit(RESTORE_CHART_LIMIT).lean(),
        Settings.find().lean(),
        User.findOne({ username: req.user.username, deletedAt: null })
          .select(
            'username role isBlocked isSalesBlocked scheme rateSetId amountLimit digit1CountLimit digit2CountLimit digit3CountLimit'
          )
          .lean(),
      ]);

    const settings = {};
    for (const d of settingsDocs) settings[d.key] = d.value;

    logInfo(
      `[restore] user=${req.user.username} role=${req.user.role} bookings=${bookings.length} sales=${sales.length} chart=${chartArchive.length}`
    );
    logMemory('memory after restore query');

    res.json({
      bookings: bookings.map((b) => ({
        billNo: b.billNo,
        username: b.username,
        rows: b.rows,
        drawName: b.drawName || '',
        businessDate: b.businessDate || null,
        createdAt: b.createdAt,
      })),
      sales: sales.map((s) => ({
        type: s.type,
        number: s.number,
        count: s.count,
        amount: s.amount,
        time: s.time,
        businessDate: s.businessDate || null,
        username: s.username,
        createdAt: s.createdAt,
      })),
      results: results.map((r) => ({
        drawCode: r.drawCode,
        date: r.date,
        prizes: r.prizes,
        compliments: r.compliments,
        manualOverride: !!r.manualOverride,
      })),
      pending: pending.map((p) => ({
        id: p._id,
        payload: p.payload,
        createdAt: p.createdAt,
      })),
      chartArchive: chartArchive.map((c) => ({
        drawCode: c.drawCode,
        date: c.date,
        drawLabel: c.drawLabel,
        prizes: c.prizes,
        compliments: c.compliments,
      })),
      settings,
      profile: profileUser
        ? {
            username: profileUser.username,
            role: profileUser.role,
            isBlocked: profileUser.isBlocked,
            isSalesBlocked: profileUser.isSalesBlocked,
            scheme: profileUser.scheme,
            rateSetId: profileUser.rateSetId,
            amountLimit: profileUser.amountLimit,
            digit1CountLimit: profileUser.digit1CountLimit,
            digit2CountLimit: profileUser.digit2CountLimit,
            digit3CountLimit: profileUser.digit3CountLimit,
          }
        : null,
      meta: {
        limits: {
          bookings: RESTORE_BOOKING_LIMIT,
          sales: RESTORE_SALE_LIMIT,
          chartArchive: RESTORE_CHART_LIMIT,
        },
        truncated: {
          bookings: bookings.length >= RESTORE_BOOKING_LIMIT,
          sales: sales.length >= RESTORE_SALE_LIMIT,
          chartArchive: chartArchive.length >= RESTORE_CHART_LIMIT,
        },
      },
    });
  } catch (e) {
    logError('restore', e);
    res.status(500).json({ error: 'Restore failed' });
  }
});

module.exports = router;
