const express = require('express');
const Booking = require('../models/Booking');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');

const router = express.Router();

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
    const filter = {
      deletedAt: null,
      createdAt: { $gte: cutoff },
      ...ownerFilter(req),
    };
    const items = await Booking.find(filter).sort({ createdAt: -1 }).lean();
    console.log(
      `[bookings] GET user=${req.user.username} role=${req.user.role} count=${items.length}`
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
    });
  } catch (e) {
    console.error('GET bookings', e);
    res.status(500).json({ error: 'Failed to fetch bookings' });
  }
});

router.post('/', authRequired, async (req, res) => {
  try {
    const body = req.body || {};
    const billNo = parseInt(body.billNo, 10);
    const createdAt = body.createdAt ? new Date(body.createdAt) : new Date();
    if (!billNo || !Array.isArray(body.rows)) {
      return res.status(400).json({ error: 'billNo and rows required' });
    }

    const businessDate = body.businessDate
      ? new Date(body.businessDate)
      : null;

    const doc = {
      billNo,
      username: body.username || req.user.username,
      ownerUsername: req.user.username,
      rows: body.rows,
      drawName: body.drawName || '',
      customerName: body.customerName || body.billNote || '',
      businessDate,
      createdAt,
      clientId: body.clientId || null,
      deletedAt: body.deleted ? new Date() : null,
    };

    const saved = await Booking.findOneAndUpdate(
      upsertFilter(req, billNo),
      { $set: doc },
      { upsert: true, new: true }
    );

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
    });
  } catch (e) {
    console.error('POST booking', e);
    res.status(500).json({ error: 'Failed to save booking' });
  }
});

/** Soft delete booking */
router.delete('/:billNo', authRequired, async (req, res) => {
  try {
    const billNo = parseInt(req.params.billNo, 10);
    const filter = { billNo, deletedAt: null, ...ownerFilter(req) };
    const updated = await Booking.findOneAndUpdate(
      filter,
      { $set: { deletedAt: new Date() } },
      { new: true }
    );
    if (!updated) return res.status(404).json({ error: 'Booking not found' });
    res.json({ ok: true, billNo });
  } catch (e) {
    res.status(500).json({ error: 'Delete failed' });
  }
});

module.exports = router;
