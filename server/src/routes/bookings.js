const express = require('express');
const Booking = require('../models/Booking');
const User = require('../models/User');
const { usedPaise, saveBooking } = require('../services/dailyBookingLimit');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');
const { parseLimit, parseSkip } = require('../utils/queryLimits');
const { logError } = require('../utils/logger');
const mongoose = require('mongoose');
const WalletAccount = require('../models/WalletAccount');
const { lockUser, applyBooking, snapshot } = require('../services/wallet');
const { settlePendingWinnings } = require('../services/walletWinnings');
const { dateKey } = require('../services/winningRules');

const router = express.Router();

router.get('/daily-limit', authRequired, async (req, res) => {
  try {
    const user = await User.findOne({ username: req.user.username, deletedAt: null }).lean();
    if (!user) return res.status(404).json({ error: 'User not found' });
    const used = await usedPaise(user.username, new Date());
    const wallet = await WalletAccount.findOne({ username: user.username }).lean();
    res.json({ enforced: true, limit: Number(user.amountLimit) || 0, used: used / 100, wallet: snapshot(wallet) });
  } catch (e) {
    res.status(500).json({ error: 'Failed to load daily limit' });
  }
});

function ownerFilter(req) {
  if (req.user.role === 'ADMIN') return {};
  return { ownerUsername: req.user.username };
}

function upsertFilter(req, billNo) {
  if (req.user.role === 'ADMIN') return { billNo };
  return { billNo, ownerUsername: req.user.username };
}

router.get('/', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const limit = parseLimit(req.query.limit);
    const skip = parseSkip(req.query.skip);
    const filter = {
      deletedAt: null,
      createdAt: { $gte: cutoff },
      ...ownerFilter(req),
    };
    const items = await Booking.find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean();
    console.log(
      `[bookings] GET user=${req.user.username} role=${req.user.role} count=${items.length} limit=${limit} skip=${skip}`
    );
    res.json({
      items: items.map((b) => ({
        billNo: b.billNo,
        username: b.username,
        rows: b.rows,
        drawName: b.drawName || '',
        customerName: b.customerName || '',
        businessDate: b.businessDate || null,
        createdAt: b.createdAt,
        clientId: b.clientId,
      })),
      meta: { limit, skip, truncated: items.length >= limit },
    });
  } catch (e) {
    logError('GET bookings', e);
    res.status(500).json({ error: 'Failed to fetch bookings' });
  }
});

router.post('/', authRequired, async (req, res) => {
  try {
    const actor = await User.findOne({ username: req.user.username, deletedAt: null }).lean();
    if (!actor || actor.role !== req.user.role || actor.isBlocked) return res.status(403).json({ error: 'Sign in with an active account' });
    const body = req.body || {};
    const billNo = parseInt(body.billNo, 10);
    const createdAt = body.createdAt ? new Date(body.createdAt) : new Date();
    if (!billNo || !Array.isArray(body.rows) || !Number.isFinite(createdAt.getTime())) {
      return res.status(400).json({ error: 'billNo and rows required' });
    }

    const businessDate = body.businessDate
      ? new Date(`${dateKey(body.businessDate)}T00:00:00Z`)
      : null;
    if (businessDate && !Number.isFinite(businessDate.getTime())) return res.status(400).json({ error: 'Valid businessDate required' });

    const doc = {
      billNo,
      username: req.user.role === 'ADMIN'
        ? (body.username || req.user.username).trim().toLowerCase()
        : req.user.username,
      ownerUsername: req.user.username,
      rows: body.rows,
      drawName: body.drawName || '',
      customerName: body.customerName || body.billNote || '',
      businessDate,
      createdAt,
      clientId: body.clientId || null,
      deletedAt: body.deleted ? new Date() : null,
    };

    const existing = await Booking.findOne(upsertFilter(req, billNo)).select('username').lean();
    if (existing) doc.username = existing.username;
    const saved = await saveBooking(doc, upsertFilter(req, billNo));
    void settlePendingWinnings();

    console.log(
      `[bookings] POST user=${req.user.username} role=${req.user.role} billNo=${saved.billNo}`
    );

    res.status(201).json({
      billNo: saved.billNo,
      username: saved.username,
      rows: saved.rows,
      drawName: saved.drawName || '',
      customerName: saved.customerName || '',
      businessDate: saved.businessDate || null,
      createdAt: saved.createdAt,
      clientId: saved.clientId,
      wallet: saved.$locals.walletSnapshot,
      amountLimit: saved.$locals.amountLimit,
    });
  } catch (e) {
    if (e.status) return res.status(e.status).json({ error: e.message, code: e.code });
    console.error('POST booking', e);
    res.status(500).json({ error: 'Failed to save booking' });
  }
});

/** Soft delete booking */
router.delete('/:billNo', authRequired, async (req, res) => {
  try {
    const actor = await User.findOne({ username: req.user.username, deletedAt: null }).lean();
    if (!actor || actor.role !== req.user.role || actor.isBlocked) return res.status(403).json({ error: 'Sign in with an active account' });
    const billNo = parseInt(req.params.billNo, 10);
    const filter = { billNo, ...ownerFilter(req) };
    const updated = await mongoose.connection.transaction(async session => {
      const existing = await Booking.findOne(filter).session(session);
      if (!existing) return null;
      const user = await lockUser(existing.username, session);
      if (existing.deletedAt) return existing;
      const doc = { ...existing.toObject(), ownerUsername: req.user.username, deletedAt: new Date() };
      await applyBooking(doc, existing, user, 0, session);
      return Booking.findOneAndUpdate(filter, { $set: {
        deletedAt: doc.deletedAt, walletTracked: doc.walletTracked,
        walletBasePaise: doc.walletBasePaise, walletDebitPaise: doc.walletDebitPaise,
      } }, { new: true, session });
    });
    if (!updated) return res.status(404).json({ error: 'Booking not found' });
    void settlePendingWinnings();
    res.json({ ok: true, billNo });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.status ? e.message : 'Delete failed', code: e.code });
  }
});

module.exports = router;
