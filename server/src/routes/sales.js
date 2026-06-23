const express = require('express');
const Sale = require('../models/Sale');
const { authRequired } = require('../middleware/auth');
const { retentionCutoff } = require('../utils/dates');

const router = express.Router();

function ownerFilter(req) {
  if (req.user.role === 'ADMIN') return {};
  return { ownerUsername: req.user.username };
}

router.get('/', authRequired, async (req, res) => {
  try {
    const cutoff = retentionCutoff();
    const items = await Sale.find({
      deletedAt: null,
      createdAt: { $gte: cutoff },
      ...ownerFilter(req),
    })
      .sort({ createdAt: -1 })
      .lean();

    res.json({
      items: items.map((s) => ({
        type: s.type,
        number: s.number,
        count: s.count,
        amount: s.amount,
        time: s.time,
        businessDate: s.businessDate || null,
        username: s.username,
        createdAt: s.createdAt,
        clientId: s.clientId,
      })),
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch sales' });
  }
});

router.post('/', authRequired, async (req, res) => {
  try {
    const body = req.body || {};
    const createdAt = body.createdAt ? new Date(body.createdAt) : new Date();
    if (!body.type || !body.number) {
      return res.status(400).json({ error: 'type and number required' });
    }

    const businessDate = body.businessDate
      ? new Date(body.businessDate)
      : null;

    const sale = await Sale.create({
      type: body.type,
      number: body.number,
      count: body.count || 0,
      amount: body.amount || 0,
      time: body.time || '',
      businessDate,
      username: body.username || req.user.username,
      ownerUsername: req.user.username,
      createdAt,
      clientId: body.clientId || null,
      deletedAt: body.deleted ? new Date() : null,
    });

    res.status(201).json({
      type: sale.type,
      number: sale.number,
      count: sale.count,
      amount: sale.amount,
      time: sale.time,
      businessDate: sale.businessDate || null,
      username: sale.username,
      createdAt: sale.createdAt,
      clientId: sale.clientId,
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to save sale' });
  }
});

module.exports = router;
