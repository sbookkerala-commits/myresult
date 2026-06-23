const path = require('path');

require('dotenv').config({
  path:
    process.env.DOTENV_PATH ||
    (process.env.NODE_ENV === 'production'
      ? path.join(__dirname, '../.env.production')
      : path.join(__dirname, '../.env')),
});

const express = require('express');
const cors = require('cors');
const cron = require('node-cron');
const { connectDb } = require('./config/db');
const { ensureAdminUser } = require('./bootstrap/ensureAdmin');
const { runRetentionJob } = require('./jobs/retention');
const { runDailyBackup } = require('./jobs/backup');

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const bookingRoutes = require('./routes/bookings');
const saleRoutes = require('./routes/sales');
const resultRoutes = require('./routes/results');
const pendingRoutes = require('./routes/pending');
const chartRoutes = require('./routes/chartArchive');
const settingsRoutes = require('./routes/settings');
const restoreRoutes = require('./routes/restore');
const backupRoutes = require('./routes/backup');

const app = express();
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

app.use(cors());
app.use(express.json({ limit: '10mb' }));

app.get('/health', (_, res) =>
  res.json({
    ok: true,
    service: 'myresult-api',
    environment: process.env.NODE_ENV || 'development',
    time: new Date().toISOString(),
    retentionDays: parseInt(process.env.RETENTION_DAYS || '20', 10),
    database: process.env.USE_EMBEDDED_MONGO === 'true' ? 'embedded' : 'atlas',
  })
);

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/bookings', bookingRoutes);
app.use('/api/sales', saleRoutes);
app.use('/api/results', resultRoutes);
app.use('/api/pending', pendingRoutes);
app.use('/api/chart-archive', chartRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/sync', restoreRoutes);
app.use('/api/backup', backupRoutes);

const publicDir = path.join(__dirname, '../public');
const fs = require('fs');
if (fs.existsSync(publicDir)) {
  app.use(express.static(publicDir, { index: 'index.html', maxAge: '1h' }));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path === '/health') return next();
    res.sendFile(path.join(publicDir, 'index.html'), (err) => {
      if (err) next();
    });
  });
  console.log(`Web app: serving static files from ${publicDir}`);
}

async function start() {
  await connectDb();
  await ensureAdminUser();

  try {
    await runRetentionJob();
  } catch (e) {
    console.error('startup retention error', e);
  }

  cron.schedule('0 2 * * *', async () => {
    try {
      await runRetentionJob();
      await runDailyBackup();
    } catch (e) {
      console.error('cron error', e);
    }
  });

  app.listen(PORT, HOST, () => {
    console.log(`API listening on ${HOST}:${PORT}`);
    console.log(`Health: /health`);
  });
}

start().catch((e) => {
  console.error('Failed to start server', e);
  process.exit(1);
});
