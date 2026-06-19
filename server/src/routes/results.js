const express = require('express');
const Result = require('../models/Result');
const ChartArchive = require('../models/ChartArchive');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff, startOfDay } = require('../utils/dates');

const router = express.Router();

router.get('/', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const items = await Result.find({
      deletedAt: null,
      date: { $gte: cutoff },
    })
      .sort({ date: -1 })
      .lean();

    res.json({
      items: items.map((r) => ({
        drawCode: r.drawCode,
        date: r.date,
        prizes: r.prizes,
        compliments: r.compliments,
      })),
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch results' });
  }
});

router.post('/', authRequired, async (req, res) => {
  try {
    const body = req.body || {};
    const drawCode = (body.drawCode || '').trim();
    const date = startOfDay(body.date ? new Date(body.date) : new Date());
    if (!drawCode) {
      return res.status(400).json({ error: 'drawCode required' });
    }

    const prizes = Array.isArray(body.prizes) ? body.prizes : [];
    const compliments = Array.isArray(body.compliments) ? body.compliments : [];

    const saved = await Result.findOneAndUpdate(
      { drawCode, date },
      {
        $set: {
          drawCode,
          date,
          prizes,
          compliments,
          updatedBy: req.user.username,
          deletedAt: null,
        },
      },
      { upsert: true, new: true }
    );

    // Permanent chart archive (never deleted by retention)
    await ChartArchive.findOneAndUpdate(
      { drawCode, date },
      {
        $set: {
          drawCode,
          date,
          drawLabel: body.drawLabel || drawCode,
          prizes,
          compliments,
          archivedBy: req.user.username,
          meta: body.meta || {},
        },
      },
      { upsert: true, new: true }
    );

    res.status(201).json({
      drawCode: saved.drawCode,
      date: saved.date,
      prizes: saved.prizes,
      compliments: saved.compliments,
    });
  } catch (e) {
    console.error('POST result', e);
    res.status(500).json({ error: 'Failed to save result' });
  }
});

module.exports = router;
