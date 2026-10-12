const express = require('express');
const Settings = require('../models/Settings');
const User = require('../models/User');
const bcrypt = require('bcryptjs');
const { authRequired, requireRoles } = require('../middleware/auth');

const router = express.Router();
const { amountLimit: readAmountLimit } = require('../utils/userLimits');

router.get('/', authRequired, async (req, res) => {
  try {
    const docs = await Settings.find().lean();
    const settings = {};
    for (const d of docs) {
      settings[d.key] = d.value;
    }
    res.json({ settings });
  } catch (e) {
    res.status(500).json({ error: 'Failed to load settings' });
  }
});

router.post('/', authRequired, async (req, res) => {
  try {
    const { key, value, users } = req.body || {};

    // Bulk user sync (admin)
    if (Array.isArray(users)) {
      if (req.user.role !== 'ADMIN') {
        return res.status(403).json({ error: 'Admin only' });
      }
      users.forEach((user) => readAmountLimit(user.amountLimit));
      for (const u of users) {
        const username = (u.username || '').trim().toLowerCase();
        if (!username) continue;
        const role = (u.role || 'AGENT').toUpperCase();
        const isAgentRole = role !== 'ADMIN';
        const existing = await User.findOne({ username });
        const passwordHash = u.password
          ? await bcrypt.hash(u.password, 10)
          : existing?.passwordHash;
        if (!passwordHash) continue;
        const agentFields = isAgentRole
          ? {
              scheme: (u.scheme || 'ALL').toString(),
              rateSetId: (u.rateSetId || 'standard').toString(),
              amountLimit: readAmountLimit(u.amountLimit),
              digit1CountLimit: parseInt(u.digit1CountLimit, 10) || 0,
              digit2CountLimit: parseInt(u.digit2CountLimit, 10) || 0,
              digit3CountLimit: parseInt(u.digit3CountLimit, 10) || 0,
            }
          : {};
        await User.findOneAndUpdate(
          { username },
          {
            $set: {
              username,
              passwordHash,
              role,
              isBlocked: !!u.isBlocked,
              isSalesBlocked: !!u.isSalesBlocked,
              deletedAt: u.deleted ? new Date() : null,
              ...agentFields,
            },
          },
          { upsert: true }
        );
      }
      return res.json({ ok: true, synced: users.length });
    }

    if (!key) {
      return res.status(400).json({ error: 'key required' });
    }
    if (key === 'walletPayment') {
      return res.status(403).json({ error: 'Use the admin wallet payment settings endpoint' });
    }

    // Price list / rate sets / draw times — admin only
    if (
      (key === 'priceList' ||
        key === 'priceListGameRates' ||
        key === 'rateSets' ||
        key === 'drawSchedules' ||
        key === 'digitCountLimits') &&
      req.user.role !== 'ADMIN'
    ) {
      return res.status(403).json({ error: 'Admin only: settings edit' });
    }

    const saved = await Settings.findOneAndUpdate(
      { key },
      { $set: { key, value, updatedBy: req.user.username } },
      { upsert: true, new: true }
    );

    res.json({ key: saved.key, value: saved.value });
  } catch (e) {
    console.error('settings', e);
    res.status(e.status || 500).json({ error: e.status ? e.message : 'Failed to save settings' });
  }
});

/** GET users list for restore (admin sees all) */
router.get('/users', authRequired, requireRoles('ADMIN', 'AGENT'), async (req, res) => {
  try {
    const users = await User.find({ deletedAt: null })
      .select(
        'username role isBlocked isSalesBlocked scheme rateSetId amountLimit digit1CountLimit digit2CountLimit digit3CountLimit'
      )
      .lean();
    res.json({ users });
  } catch (e) {
    res.status(500).json({ error: 'Failed to load users' });
  }
});

module.exports = router;
