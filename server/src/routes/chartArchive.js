const express = require('express');
const ChartArchive = require('../models/ChartArchive');
const { authRequired } = require('../middleware/auth');

const router = express.Router();

router.get('/', authRequired, async (req, res) => {
  try {
    const { drawCode, from, to, limit = 500 } = req.query;
    const filter = {};
    if (drawCode) filter.drawCode = drawCode;
    if (from || to) {
      filter.date = {};
      if (from) filter.date.$gte = new Date(from);
      if (to) filter.date.$lte = new Date(to);
    }

    const items = await ChartArchive.find(filter)
      .sort({ date: -1 })
      .limit(Math.min(parseInt(limit, 10) || 500, 2000))
      .lean();

    res.json({
      items: items.map((c) => ({
        drawCode: c.drawCode,
        date: c.date,
        drawLabel: c.drawLabel,
        prizes: c.prizes,
        compliments: c.compliments,
        meta: c.meta,
        archivedAt: c.updatedAt,
      })),
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch chart archive' });
  }
});

module.exports = router;
