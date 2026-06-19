const express = require('express');
const { authRequired, requireRoles } = require('../middleware/auth');
const { runDailyBackup } = require('../jobs/backup');

const router = express.Router();

/** Manual daily backup trigger — admin only */
router.post('/', authRequired, requireRoles('ADMIN'), async (req, res) => {
  try {
    const file = await runDailyBackup();
    res.json({ ok: true, file });
  } catch (e) {
    res.status(500).json({ error: 'Backup failed' });
  }
});

module.exports = router;
