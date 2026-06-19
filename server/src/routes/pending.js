const express = require('express');
const Pending = require('../models/Pending');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');

const router = express.Router();

router.get('/', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const filter = {
      deletedAt: null,
      createdAt: { $gte: cutoff },
      ownerUsername: req.user.username,
    };
    const items = await Pending.find(filter).sort({ createdAt: -1 }).lean();
    res.json({ items });
  } catch (e) {
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
    res.status(500).json({ error: 'Delete failed' });
  }
});

module.exports = router;
