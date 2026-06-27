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
        manualOverride: !!r.manualOverride,
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
    const day = startOfDay(body.date ? new Date(body.date) : new Date());
    if (!drawCode) {
      return res.status(400).json({ error: 'drawCode required' });
    }

    const prizes = Array.isArray(body.prizes) ? body.prizes : [];
    const compliments = Array.isArray(body.compliments) ? body.compliments : [];
    const manualOverride = body.manualOverride === true;

    const existing = await Result.findOne({ drawCode, date: day, deletedAt: null }).lean();
    if (existing?.manualOverride && !manualOverride) {
      return res.json({
        drawCode: existing.drawCode,
        date: existing.date,
        prizes: existing.prizes,
        compliments: existing.compliments,
        manualOverride: true,
        skipped: true,
      });
    }

    const saved = await Result.findOneAndUpdate(
      { drawCode, date: day },
      {
        $set: {
          drawCode,
          date: day,
          prizes,
          compliments,
          manualOverride,
          updatedBy: req.user.username,
          deletedAt: null,
        },
      },
      { upsert: true, new: true }
    );

    // Permanent chart archive (never deleted by retention)
    await ChartArchive.findOneAndUpdate(
      { drawCode, date: day },
      {
        $set: {
          drawCode,
          date: day,
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
      manualOverride: !!saved.manualOverride,
    });
  } catch (e) {
    console.error('POST result', e);
    res.status(500).json({ error: 'Failed to save result' });
  }
});

router.delete('/:drawCode/:date', authRequired, async (req, res) => {
  try {
    const drawCode = (req.params.drawCode || '').trim().toUpperCase();
    const day = startOfDay(new Date(req.params.date));
    if (!drawCode) {
      return res.status(400).json({ error: 'drawCode required' });
    }

    await Result.findOneAndUpdate(
      { drawCode, date: day },
      {
        $set: {
          deletedAt: new Date(),
          updatedBy: req.user.username,
        },
      },
    );

    res.json({ ok: true, drawCode, date: day });
  } catch (e) {
    console.error('DELETE result', e);
    res.status(500).json({ error: 'Failed to delete result' });
  }
});

module.exports = router;
