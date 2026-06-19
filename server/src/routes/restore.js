const express = require('express');
const Booking = require('../models/Booking');
const Sale = require('../models/Sale');
const Result = require('../models/Result');
const Pending = require('../models/Pending');
const ChartArchive = require('../models/ChartArchive');
const Settings = require('../models/Settings');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');

const router = express.Router();

/** Login restore — cloud → local SQLite on device */
router.get('/restore', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const owner =
      req.user.role === 'ADMIN' ? {} : { ownerUsername: req.user.username };

    const [bookings, sales, results, pending, chartArchive, settingsDocs] =
      await Promise.all([
        Booking.find({ deletedAt: null, createdAt: { $gte: cutoff }, ...owner })
          .sort({ createdAt: -1 })
          .lean(),
        Sale.find({ deletedAt: null, createdAt: { $gte: cutoff }, ...owner })
          .sort({ createdAt: -1 })
          .lean(),
        Result.find({ deletedAt: null, date: { $gte: cutoff } })
          .sort({ date: -1 })
          .lean(),
        Pending.find({
          deletedAt: null,
          createdAt: { $gte: cutoff },
          ownerUsername: req.user.username,
        })
          .sort({ createdAt: -1 })
          .lean(),
        ChartArchive.find().sort({ date: -1 }).limit(5000).lean(),
        Settings.find().lean(),
      ]);

    const settings = {};
    for (const d of settingsDocs) settings[d.key] = d.value;

    console.log(
      `[restore] user=${req.user.username} role=${req.user.role} bookings=${bookings.length}`
    );

    res.json({
      bookings: bookings.map((b) => ({
        billNo: b.billNo,
        username: b.username,
        rows: b.rows,
        createdAt: b.createdAt,
      })),
      sales: sales.map((s) => ({
        type: s.type,
        number: s.number,
        count: s.count,
        amount: s.amount,
        time: s.time,
        username: s.username,
        createdAt: s.createdAt,
      })),
      results: results.map((r) => ({
        drawCode: r.drawCode,
        date: r.date,
        prizes: r.prizes,
        compliments: r.compliments,
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
    });
  } catch (e) {
    console.error('restore', e);
    res.status(500).json({ error: 'Restore failed' });
  }
});

module.exports = router;
