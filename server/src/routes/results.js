const express = require('express');
const Result = require('../models/Result');
const User = require('../models/User');
const mongoose = require('mongoose');
const { settlePendingWinnings } = require('../services/walletWinnings');
const { HOURS, dateKey } = require('../services/winningRules');
const ChartArchive = require('../models/ChartArchive');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');
const { parseLimit, parseSkip } = require('../utils/queryLimits');
const { logError } = require('../utils/logger');

const router = express.Router();

router.get('/', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const limit = parseLimit(req.query.limit, 2000);
    const skip = parseSkip(req.query.skip);
    const items = await Result.find({
      deletedAt: null,
      date: { $gte: cutoff },
    })
      .sort({ date: -1 })
      .skip(skip)
      .limit(limit)
      .lean();

    res.json({
      items: items.map((r) => ({
        drawCode: r.drawCode,
        date: r.date,
        prizes: r.prizes,
        compliments: r.compliments,
        manualOverride: !!r.manualOverride,
      })),
      meta: { limit, skip, truncated: items.length >= limit },
    });
  } catch (e) {
    logError('GET results', e);
    res.status(500).json({ error: 'Failed to fetch results' });
  }
});

router.post('/', authRequired, async (req, res) => {
  try {
    const body = req.body || {};
    const drawCode = (body.drawCode || '').trim().toUpperCase();
    const dayKey = body.date ? dateKey(body.date) : dateKey(new Date(Date.now() + 330 * 60000));
    const day = new Date(`${dayKey}T00:00:00Z`);
    if (!HOURS[drawCode] || !Number.isFinite(day.getTime())) {
      return res.status(400).json({ error: 'Valid drawCode and date required' });
    }

    const actor = await User.findOne({ username: req.user.username, role: 'ADMIN', deletedAt: null, isBlocked: false }).lean();
    // Customer devices may still fetch web results locally. They cannot change
    // the authoritative result used to credit money, including with a stale JWT.
    if (!actor) return res.json({ skipped: true, reason: 'Admin result sync required' });

    const prizes = Array.isArray(body.prizes) ? body.prizes.map(String) : [];
    const compliments = Array.isArray(body.compliments) ? body.compliments.map(String) : [];
    if (prizes.length > 5 || compliments.length > 30 || [...prizes, ...compliments].some(n => n !== '---' && !/^\d{3,6}$/.test(n))) {
      return res.status(400).json({ error: 'Invalid result numbers' });
    }
    if (prizes[0] && prizes[0] !== '---') prizes[0] = prizes[0].slice(-3);
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

    const saved = await mongoose.connection.transaction(async session => {
      const current = await Result.findOne({ drawCode, date: day, deletedAt: null }).session(session);
      if (current?.manualOverride && !manualOverride) return current;
      return Result.findOneAndUpdate(
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
          walletAuthorizedAt: new Date(),
          walletPending: true,
        },
        $inc: { walletResultRevision: 1 },
      },
      { upsert: true, new: true, session }
      );
    });
    void settlePendingWinnings();

    // Permanent chart archive (never deleted by retention)
    await ChartArchive.findOneAndUpdate(
      { drawCode, date: day },
      {
        $set: {
          drawCode,
          date: day,
          drawLabel: body.drawLabel || drawCode,
          prizes: saved.prizes,
          compliments: saved.compliments,
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
    if (!await User.exists({ username: req.user.username, role: 'ADMIN', deletedAt: null, isBlocked: false })) {
      return res.status(403).json({ error: 'Admin access required' });
    }
    const drawCode = (req.params.drawCode || '').trim().toUpperCase();
    const day = new Date(`${dateKey(req.params.date)}T00:00:00Z`);
    if (!HOURS[drawCode] || !Number.isFinite(day.getTime())) {
      return res.status(400).json({ error: 'Valid drawCode and date required' });
    }

    await Result.findOneAndUpdate(
      { drawCode, date: day },
      {
        $set: {
          deletedAt: new Date(),
          updatedBy: req.user.username,
          walletPending: true,
        },
        $inc: { walletResultRevision: 1 },
      },
    );
    void settlePendingWinnings();

    res.json({ ok: true, drawCode, date: day });
  } catch (e) {
    console.error('DELETE result', e);
    res.status(500).json({ error: 'Failed to delete result' });
  }
});

module.exports = router;
