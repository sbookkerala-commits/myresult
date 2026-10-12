function amountLimit(value) {
  const amount = value == null || value === '' ? 0 : Number(value);
  if (!Number.isFinite(amount) || amount < 0) {
    const error = new Error('Daily amount limit must be a non-negative amount');
    error.status = 400;
    throw error;
  }
  return Math.round(amount * 100) / 100;
}

module.exports = { amountLimit };
