/** Hard caps to prevent OOM on Render's limited RAM. */
const DEFAULT_LIST_LIMIT = parseInt(process.env.API_LIST_LIMIT || '2000', 10);
const MAX_LIST_LIMIT = parseInt(process.env.API_MAX_LIST_LIMIT || '5000', 10);
const RESTORE_BOOKING_LIMIT = parseInt(
  process.env.RESTORE_BOOKING_LIMIT || '3000',
  10
);
const RESTORE_SALE_LIMIT = parseInt(process.env.RESTORE_SALE_LIMIT || '5000', 10);
const RESTORE_CHART_LIMIT = parseInt(
  process.env.RESTORE_CHART_LIMIT || '1000',
  10
);
const BACKUP_BATCH_SIZE = parseInt(process.env.BACKUP_BATCH_SIZE || '500', 10);
const BACKUP_MAX_DOCS = parseInt(process.env.BACKUP_MAX_DOCS || '10000', 10);

function parseLimit(raw, fallback = DEFAULT_LIST_LIMIT) {
  const n = parseInt(raw, 10);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(n, MAX_LIST_LIMIT);
}

function parseSkip(raw) {
  const n = parseInt(raw, 10);
  if (!Number.isFinite(n) || n < 0) return 0;
  return n;
}

module.exports = {
  DEFAULT_LIST_LIMIT,
  MAX_LIST_LIMIT,
  RESTORE_BOOKING_LIMIT,
  RESTORE_SALE_LIMIT,
  RESTORE_CHART_LIMIT,
  BACKUP_BATCH_SIZE,
  BACKUP_MAX_DOCS,
  parseLimit,
  parseSkip,
};
