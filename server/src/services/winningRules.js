// Payout rules shared with the app's unified DEAR1 winning report template.
const HOURS = { DEAR1: 13, LSK3: 15, DEAR6: 18, DEAR8: 20 };
const LABELS = { DEAR1: 'DEAR 1 PM', LSK3: 'LSK 3 PM', DEAR6: 'DEAR 6 PM', DEAR8: 'DEAR 8 PM' };
const SUPER = [[5000, 0], [500, 0], [250, 0], [100, 0], [50, 0], [20, 0]];
const BOX = [[3000, 300], [800, 30], [800, 30], [800, 30], [800, 30], [800, 30], [3800, 330], [1600, 60]];
const digits = value => `${value ?? ''}`.replace(/\D/g, '');
function rowType(row) {
  const [draw, suffix] = `${row.type || ''}`.toUpperCase().split('-');
  return HOURS[draw] && ['SUPER', 'BOX', 'A', 'B', 'C', 'AB', 'BC', 'AC'].includes(suffix) ? { draw, suffix } : null;
}
function dateKey(value) {
  if (typeof value === 'string') {
    const match = /^\d{4}-\d{2}-\d{2}/.exec(value);
    if (match) {
      const parsed = new Date(`${match[0]}T00:00:00Z`);
      return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === match[0] ? match[0] : null;
    }
  }
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString().slice(0, 10) : null;
}
function billDate(bill) {
  return bill.businessDate ? dateKey(bill.businessDate) : dateKey(new Date(new Date(bill.createdAt).getTime() + 330 * 60000));
}
function drawCutoff(draw, date, schedules = []) {
  const schedule = Array.isArray(schedules) ? schedules.find(s => s.drawTime === LABELS[draw]) : null;
  const hour = Number.isInteger(schedule?.closeHour) ? schedule.closeHour : HOURS[draw];
  const minute = Number.isInteger(schedule?.closeMinute) ? schedule.closeMinute : 0;
  return new Date(new Date(`${dateKey(date)}T00:00:00Z`).getTime() + (hour * 60 + minute - 330) * 60000);
}
function schemesForUser(priceList, username) {
  const stored = priceList?.[username];
  return Array.isArray(stored) ? structuredClone(stored) : [];
}
function scheme(schemes, suffix) {
  return schemes.find(s => `${s.name}`.toUpperCase() === `DEAR1-${suffix}`);
}
function parts(schemes, suffix, index) {
  let fallback = suffix === 'SUPER' ? SUPER[index] : suffix === 'BOX' ? BOX[index] : suffix.length === 1 ? [100, 0] : [700, 30];
  if (!fallback) return { base: 0, superAmount: 0 };
  const configured = scheme(schemes, suffix)?.rows?.[index];
  if (suffix === 'SUPER' && scheme(schemes, suffix) && !Array.isArray(configured)) {
    fallback = [[5000, 400], [500, 50], [250, 20], [100, 20], [50, 20], [20, 10]][index];
  }
  let base = fallback[0], superAmount = fallback[1];
  if (Array.isArray(configured)) {
    // Flutter coercePrizeRows produces integer rupee cells (including zero).
    base = Math.trunc(Number(configured[2]) || 0);
    superAmount = Math.trunc(Number(configured[3]) || 0);
  }
  if (suffix.length === 1) superAmount = 0;
  else if (superAmount <= 0 && (suffix === 'BOX' || suffix.length === 2)) superAmount = fallback[1];
  return { base, superAmount };
}
function unitWinning(row, result, schemes = []) {
  const type = rowType(row);
  if (!type || type.draw !== result.drawCode) return null;
  const number = digits(row.number);
  const prizes = result.prizes.map(digits);
  const first = prizes[0]?.slice(-3);
  if (first?.length !== 3) return null;
  let index = 0;
  if (type.suffix.length === 1) {
    const position = { A: 0, B: 1, C: 2 }[type.suffix];
    if (number !== first[position]) return null;
  } else if (type.suffix.length === 2) {
    const positions = { AB: [0, 1], BC: [1, 2], AC: [0, 2] }[type.suffix];
    if (number !== positions.map(p => first[p]).join('')) return null;
  } else if (type.suffix === 'BOX') {
    if (number.length !== 3 || number.split('').sort().join('') !== first.split('').sort().join('')) return null;
    const twoSame = new Set(first).size === 2;
    index = (twoSame ? 6 : 0) + (number === first ? 0 : 1);
  } else {
    index = prizes.slice(0, 5).findIndex((p, i) => number === (i === 0 ? first : p));
    if (index < 0 && result.compliments.map(digits).includes(number)) index = 5;
    if (index < 0) return null;
  }
  return parts(schemes, type.suffix, index);
}
function winningForBill(bill, result, schemes = []) {
  let amountPaise = 0;
  const lines = [];
  for (const row of bill.rows) {
    const count = Number(row.count);
    if (!Number.isSafeInteger(count) || count <= 0) continue;
    const payout = unitWinning(row, result, schemes);
    if (!payout) continue;
    const basePaise = Math.round(payout.base * count * 100);
    const superPaise = Math.round(payout.superAmount * count * 100);
    const total = basePaise + superPaise;
    if (!Number.isSafeInteger(total) || total < 0) throw new Error('Invalid winning amount');
    if (total > 0) lines.push({ type: row.type, number: digits(row.number), count, basePaise, superPaise, amountPaise: total });
    amountPaise += total;
  }
  if (!Number.isSafeInteger(amountPaise)) throw new Error('Winning amount exceeds supported range');
  return { amountPaise, lines };
}
function saleAmount(row, user, settings) {
  const type = rowType(row);
  if (!type) return null;
  const group = type.suffix.length === 1 ? 1 : type.suffix.length === 2 ? 2 : 3;
  const fallback = group === 1 ? 12 : 10;
  const rates = settings.priceListGameRates?.[user.username] || {};
  const prefix = { DEAR1: 'Dear1', DEAR6: 'Dear6', DEAR8: 'Dear8', LSK3: 'Lsk3' }[type.draw];
  const custom = scheme(schemesForUser(settings.priceList, user.username), type.suffix)?.rate;
  const assigned = settings.rateSets?.find(r => r.id === user.rateSetId);
  const assignedFallback = user.rateSetId === 'economy' ? (group === 1 ? 10 : 8) : fallback;
  const rate = type.suffix === 'SUPER' && rates.superDcRate > 0 ? Number(rates.superDcRate) :
    rates[`rate${prefix}D${group}`] > 0 ? Number(rates[`rate${prefix}D${group}`]) :
    Number(custom) > 0 && Number(custom) !== fallback ? Number(custom) :
    Number(assigned?.[`group${group}Rate`]) || assignedFallback;
  const multiplier = [0, 1, .75, .5, .25][Math.min(4, Math.max(1, Math.trunc(Number(rates.billingScheme) || 1)))];
  return Math.round(rate * Number(row.count) * multiplier * 100);
}
module.exports = { HOURS, LABELS, rowType, dateKey, billDate, drawCutoff, schemesForUser, winningForBill, saleAmount };
