const express = require('express');
const bcrypt = require('bcryptjs');
const User = require('../models/User');
const { authRequired, requireRoles } = require('../middleware/auth');

const router = express.Router();

/** Current logged-in user profile (all roles) — for ~1s app sync */
router.get('/me', authRequired, async (req, res) => {
  try {
    const user = await User.findOne({
      username: req.user.username,
      deletedAt: null,
    })
      .select(
        'username role isBlocked isSalesBlocked scheme rateSetId amountLimit digit1CountLimit digit2CountLimit digit3CountLimit'
      )
      .lean();
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ user });
  } catch (e) {
    res.status(500).json({ error: 'Failed to load profile' });
  }
});

router.get('/', authRequired, requireRoles('ADMIN', 'AGENT'), async (req, res) => {
  try {
    const users = await User.find({ deletedAt: null })
      .select(
        'username role isBlocked isSalesBlocked scheme rateSetId amountLimit digit1CountLimit digit2CountLimit digit3CountLimit createdAt'
      )
      .lean();
    res.json({ users });
  } catch (e) {
    res.status(500).json({ error: 'Failed to load users' });
  }
});

function readAgentFields(body) {
  const scheme = (body.scheme || 'ALL').toString().trim() || 'ALL';
  const rateSetId = (body.rateSetId || 'standard').toString().trim() || 'standard';
  const amountLimit = Number(body.amountLimit) || 0;
  const digit1CountLimit = parseInt(body.digit1CountLimit, 10) || 0;
  const digit2CountLimit = parseInt(body.digit2CountLimit, 10) || 0;
  const digit3CountLimit = parseInt(body.digit3CountLimit, 10) || 0;
  return {
    scheme,
    rateSetId,
    amountLimit,
    digit1CountLimit,
    digit2CountLimit,
    digit3CountLimit,
  };
}

router.post('/', authRequired, requireRoles('ADMIN', 'AGENT'), async (req, res) => {
  try {
    const { username, password, role, isBlocked, isSalesBlocked } = req.body || {};
    const u = (username || '').trim().toLowerCase();
    const r = (role || 'AGENT').toUpperCase();
    const pw = (password || '').trim();
    const agentFields = readAgentFields(req.body || {});

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
    const isAgentRole = r === 'AGENT' || r === 'SUBAGENT';
    const user = await User.create({
      username: u,
      passwordHash,
      role: r,
      isBlocked: !!isBlocked,
      isSalesBlocked: !!isSalesBlocked,
      createdBy: req.user.username,
      ...(isAgentRole ? agentFields : {}),
    });

    res.status(201).json({
      username: user.username,
      role: user.role,
      isBlocked: user.isBlocked,
      isSalesBlocked: user.isSalesBlocked,
      scheme: user.scheme,
      rateSetId: user.rateSetId,
      amountLimit: user.amountLimit,
      digit1CountLimit: user.digit1CountLimit,
      digit2CountLimit: user.digit2CountLimit,
      digit3CountLimit: user.digit3CountLimit,
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to create user' });
  }
});

router.patch('/:username', authRequired, requireRoles('ADMIN'), async (req, res) => {
  try {
    const username = req.params.username.trim().toLowerCase();
    const { role, isBlocked, isSalesBlocked, password } = req.body || {};
    const update = {};
    if (role) update.role = role.toUpperCase();
    if (typeof isBlocked === 'boolean') update.isBlocked = isBlocked;
    if (typeof isSalesBlocked === 'boolean') update.isSalesBlocked = isSalesBlocked;
    if (password?.trim()) {
      update.passwordHash = await bcrypt.hash(password.trim(), 10);
    }
    if (req.body?.scheme != null) update.scheme = readAgentFields(req.body).scheme;
    if (req.body?.rateSetId != null) update.rateSetId = readAgentFields(req.body).rateSetId;
    if (req.body?.amountLimit != null) update.amountLimit = readAgentFields(req.body).amountLimit;
    if (req.body?.digit1CountLimit != null) {
      update.digit1CountLimit = readAgentFields(req.body).digit1CountLimit;
    }
    if (req.body?.digit2CountLimit != null) {
      update.digit2CountLimit = readAgentFields(req.body).digit2CountLimit;
    }
    if (req.body?.digit3CountLimit != null) {
      update.digit3CountLimit = readAgentFields(req.body).digit3CountLimit;
    }
    const user = await User.findOneAndUpdate(
      { username, deletedAt: null },
      { $set: update },
      { new: true }
    ).select(
      'username role isBlocked isSalesBlocked scheme rateSetId amountLimit digit1CountLimit digit2CountLimit digit3CountLimit'
    );
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
