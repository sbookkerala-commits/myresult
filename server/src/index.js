const path = require('path');
const fs = require('fs');

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
const { connectDb, disconnectDb, isDbReady } = require('./config/db');
const { ensureAdminUser } = require('./bootstrap/ensureAdmin');
const { runRetentionJob } = require('./jobs/retention');
const { runDailyBackup } = require('./jobs/backup');
const {
  logInfo,
  logWarn,
  logError,
  logMemory,
  memorySnapshot,
} = require('./utils/logger');

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
const BODY_LIMIT = process.env.JSON_BODY_LIMIT || '2mb';
const SERVE_STATIC =
  process.env.SERVE_STATIC_WEB === 'true' ||
  process.env.SERVE_STATIC_WEB === '1';

let server = null;
let shuttingDown = false;
let memoryTimer = null;

// ── Global process handlers (prevent silent fatal exits) ───────────────────
process.on('uncaughtException', (err) => {
  logError('uncaughtException — process will stay up if possible', err);
  logMemory('memory after uncaughtException');
  // Do not exit immediately on Render — log and keep serving if healthy.
  // Exit only for clearly fatal programming errors after a short grace period
  // when explicitly enabled.
  if (process.env.EXIT_ON_UNCAUGHT === 'true') {
    setTimeout(() => process.exit(1), 1000).unref();
  }
});

process.on('unhandledRejection', (reason) => {
  logError('unhandledRejection', reason instanceof Error ? reason : new Error(String(reason)));
  logMemory('memory after unhandledRejection');
});

process.on('warning', (warning) => {
  logWarn(`Node warning: ${warning.name}: ${warning.message}`);
});

app.use(cors());
app.use(express.json({ limit: BODY_LIMIT }));

// Reject API work when Mongo is down (avoid cascading failures / hung handlers)
app.use('/api', (req, res, next) => {
  if (!isDbReady()) {
    return res.status(503).json({
      error: 'Database unavailable',
      retry: true,
    });
  }
  next();
});

app.get('/health', (_, res) =>
  res.json({
    ok: true,
    service: 'myresult-api',
    features: { dailyAmountLimit: 1 },
    environment: process.env.NODE_ENV || 'development',
    time: new Date().toISOString(),
    retentionDays: parseInt(process.env.RETENTION_DAYS || '20', 10),
    database: process.env.USE_EMBEDDED_MONGO === 'true' ? 'embedded' : 'atlas',
    dbReady: isDbReady(),
    memory: memorySnapshot(),
    uptimeSec: Math.round(process.uptime()),
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

// Static Flutter web is OPTIONAL — serving ~37MB CanvasKit assets on a
// 512MB Render instance is a common cause of exit status 134 (SIGABRT/OOM).
const publicDir = path.join(__dirname, '../public');
if (SERVE_STATIC && fs.existsSync(publicDir)) {
  app.use(express.static(publicDir, { index: 'index.html', maxAge: '1h' }));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path === '/health') return next();
    res.sendFile(path.join(publicDir, 'index.html'), (err) => {
      if (err) next(err);
    });
  });
  logInfo(`Web app: serving static files from ${publicDir}`);
} else if (fs.existsSync(publicDir) && !SERVE_STATIC) {
  logInfo(
    'Static web folder present but SERVE_STATIC_WEB is not enabled (recommended for Render API)'
  );
}

// Express error middleware — keep process alive, return JSON
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
  logError(`Express error ${req.method} ${req.originalUrl}`, err);
  if (res.headersSent) return;
  const status = err.status || err.statusCode || 500;
  res.status(status).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'production' ? undefined : err.message,
  });
});

async function gracefulShutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logInfo(`Shutdown started (${signal})`);
  logMemory('memory on shutdown');
  if (memoryTimer) clearInterval(memoryTimer);

  const forceTimer = setTimeout(() => {
    logWarn('Forced exit after shutdown timeout');
    process.exit(1);
  }, 15000);
  forceTimer.unref();

  try {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
      logInfo('HTTP server closed');
    }
    await disconnectDb();
    logInfo('Shutdown complete');
    process.exit(0);
  } catch (err) {
    logError('Shutdown error', err);
    process.exit(1);
  }
}

async function start() {
  logInfo('Server starting', {
    node: process.version,
    env: process.env.NODE_ENV || 'development',
    host: HOST,
    port: PORT,
    pid: process.pid,
    serveStatic: SERVE_STATIC,
    bodyLimit: BODY_LIMIT,
  });
  logMemory('memory at startup');

  await connectDb();
  await ensureAdminUser();

  try {
    await runRetentionJob();
  } catch (e) {
    logError('startup retention error', e);
  }

  cron.schedule('0 2 * * *', async () => {
    try {
      logInfo('Nightly cron started');
      logMemory('memory before cron');
      await runRetentionJob();
      await runDailyBackup();
      logMemory('memory after cron');
    } catch (e) {
      logError('cron error', e);
    }
  });

  // Periodic memory telemetry (helps diagnose Render 134 / OOM)
  const memEveryMs = parseInt(process.env.MEMORY_LOG_MS || '300000', 10);
  memoryTimer = setInterval(() => {
    const snap = memorySnapshot();
    logInfo('periodic memory', snap);
    if (snap.heapUsedMb > 350) {
      logWarn('High heap usage — risk of OOM on small Render plans', snap);
      if (global.gc) {
        try {
          global.gc();
          logInfo('Forced GC after high heap', memorySnapshot());
        } catch (_) {
          /* ignore */
        }
      }
    }
  }, memEveryMs);
  if (memoryTimer.unref) memoryTimer.unref();

  server = app.listen(PORT, HOST, () => {
    logInfo(`API listening on ${HOST}:${PORT}`);
    logInfo('Health: /health');
    logMemory('memory after listen');
  });

  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;

  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
  process.on('SIGINT', () => gracefulShutdown('SIGINT'));
}

start().catch((e) => {
  logError('Failed to start server', e);
  process.exit(1);
});
