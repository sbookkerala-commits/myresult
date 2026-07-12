function ts() {
  return new Date().toISOString();
}

function memorySnapshot() {
  const m = process.memoryUsage();
  return {
    rssMb: Math.round((m.rss / 1024 / 1024) * 10) / 10,
    heapUsedMb: Math.round((m.heapUsed / 1024 / 1024) * 10) / 10,
    heapTotalMb: Math.round((m.heapTotal / 1024 / 1024) * 10) / 10,
    externalMb: Math.round((m.external / 1024 / 1024) * 10) / 10,
  };
}

function logInfo(msg, extra) {
  if (extra !== undefined) {
    console.log(`[${ts()}] [INFO] ${msg}`, extra);
  } else {
    console.log(`[${ts()}] [INFO] ${msg}`);
  }
}

function logWarn(msg, extra) {
  if (extra !== undefined) {
    console.warn(`[${ts()}] [WARN] ${msg}`, extra);
  } else {
    console.warn(`[${ts()}] [WARN] ${msg}`);
  }
}

function logError(msg, err) {
  const stack =
    err && typeof err === 'object' && err.stack
      ? err.stack
      : err
        ? String(err)
        : '';
  console.error(`[${ts()}] [ERROR] ${msg}${stack ? `\n${stack}` : ''}`);
}

function logMemory(label = 'memory') {
  logInfo(`${label}`, memorySnapshot());
}

module.exports = {
  ts,
  memorySnapshot,
  logInfo,
  logWarn,
  logError,
  logMemory,
};
