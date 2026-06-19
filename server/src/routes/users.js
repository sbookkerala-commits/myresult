const express = require('express');
const bcrypt = require('bcryptjs');
const User = require('../models/User');
const { authRequired, requireRoles } = require('../middleware/auth');

const router = express.Router();

router.get('/', authRequired, requireRoles('ADMIN', 'AGENT'), async (req, res) => {
  try {
    const users = await User.find({ deletedAt: null })
      .select('username role isBlocked createdAt')
      .lean();
    res.json({ users });
  } catch (e) {
    res.status(500).json({ error: 'Failed to load users' });
  }
});

router.post('/', authRequired, requireRoles('ADMIN', 'AGENT'), async (req, res) => {
  try {
    const { username, password, role } = req.body || {};
    const u = (username || '').trim().toLowerCase();
    const r = (role || 'AGENT').toUpperCase();
    const pw = (password || '').trim();

    if (!u || !pw) {
      return res.status(400).json({ error: 'username and password required' });
    }

    const allowed =
      req.user.role === 'ADMIN'
        ? ['ADMIN', 'AGENT', 'SUBAGENT', 'CUSTOMER']
        : ['SUBAGENT', 'CUSTOMER'];
    if (!allowed.includes(r)) {
      return res.status(403).json({ error: 'Cannot create this role' });
    }

    const exists = await User.findOne({ username: u, deletedAt: null });
    if (exists) return res.status(409).json({ error: 'Username exists' });

    const passwordHash = await bcrypt.hash(pw, 10);
    const user = await User.create({
      username: u,
      passwordHash,
      role: r,
      createdBy: req.user.username,
    });

    res.status(201).json({
      username: user.username,
      role: user.role,
      isBlocked: user.isBlocked,
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to create user' });
  }
});

router.patch('/:username', authRequired, requireRoles('ADMIN'), async (req, res) => {
  try {
    const username = req.params.username.trim().toLowerCase();
    const { role, isBlocked, password } = req.body || {};
    const update = {};
    if (role) update.role = role.toUpperCase();
    if (typeof isBlocked === 'boolean') update.isBlocked = isBlocked;
    if (password?.trim()) {
      update.passwordHash = await bcrypt.hash(password.trim(), 10);
    }
    const user = await User.findOneAndUpdate(
      { username, deletedAt: null },
      { $set: update },
      { new: true }
    ).select('username role isBlocked');
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json(user);
  } catch (e) {
    res.status(500).json({ error: 'Update failed' });
  }
});

/** Soft delete user */
router.delete('/:username', authRequired, requireRoles('ADMIN'), async (req, res) => {
  try {
    const username = req.params.username.trim().toLowerCase();
    if (username === req.user.username) {
      return res.status(400).json({ error: 'Cannot delete yourself' });
    }
    const user = await User.findOneAndUpdate(
      { username, deletedAt: null },
      { $set: { deletedAt: new Date() } },
      { new: true }
    );
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: 'Delete failed' });
  }
});

module.exports = router;
