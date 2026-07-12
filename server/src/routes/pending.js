const express = require('express');
const Pending = require('../models/Pending');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');
const { parseLimit, parseSkip } = require('../utils/queryLimits');
const { logError } = require('../utils/logger');

const router = express.Router();

router.get('/', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const filter = {
      deletedAt: null,
      createdAt: { $gte: cutoff },
      ownerUsername: req.user.username,
    };
    const limit = parseLimit(req.query.limit, 1000);
    const skip = parseSkip(req.query.skip);
    const items = await Pending.find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean();
    res.json({
      items,
      meta: { limit, skip, truncated: items.length >= limit },
    });
  } catch (e) {
    logError('GET pending', e);
    res.status(500).json({ error: 'Failed to fetch pending' });
  }
});

router.post('/', authRequired, async (req, res) => {
  try {
    const payload = req.body?.payload ?? req.body;
    if (!payload) return res.status(400).json({ error: 'payload required' });
    const doc = await Pending.create({
      ownerUsername: req.user.username,
      payload,
    });
    res.status(201).json({ id: doc._id, createdAt: doc.createdAt });
  } catch (e) {
    logError('POST pending', e);
    res.status(500).json({ error: 'Failed to save pending' });
  }
});

router.delete('/:id', authRequired, async (req, res) => {
  try {
    const updated = await Pending.findOneAndUpdate(
      { _id: req.params.id, ownerUsername: req.user.username, deletedAt: null },
      { $set: { deletedAt: new Date() } },
      { new: true }
    );
    if (!updated) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true });
  } catch (e) {
    logError('DELETE pending', e);
    res.status(500).json({ error: 'Delete failed' });
  }
});

module.exports = router;
