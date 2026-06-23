function retentionCutoff() {
  const days = parseInt(process.env.RETENTION_DAYS || '20', 10);
  const d = new Date();
  d.setDate(d.getDate() - days);
  d.setHours(0, 0, 0, 0);
  return d;
}

function startOfDay(d = new Date()) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

module.exports = { retentionCutoff, startOfDay };
