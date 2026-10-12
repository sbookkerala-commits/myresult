const express = require('express');
const User = require('../models/User');
const Settings = require('../models/Settings');
const Account = require('../models/WalletAccount');
const Entry = require('../models/WalletEntry');
const Payment = require('../models/WalletPayment');
const Device = require('../models/NotificationDevice');
const { authRequired } = require('../middleware/auth');
const { error, money, snapshot, adminCredit, reviewPayment } = require('../services/wallet');
const { deliverPendingNotifications, configureCredential, credentialConfigured, messaging } = require('../services/paymentNotifications');
const router = express.Router();
router.use(authRequired, async (req, res, next) => {
  try {
    req.walletUser = await User.findOne({ username: req.user.username, deletedAt: null, isBlocked: false }).lean();
    if (!req.walletUser) throw error('Account unavailable', 403);
    next();
  } catch (e) { next(e); }
});
function adminOnly(req) { if (req.walletUser.role !== 'ADMIN') throw error('Admin access required', 403); }
function username(req) {
  const name = `${req.query.username || req.user.username}`.trim().toLowerCase();
  if (name !== req.user.username) adminOnly(req);
  return name;
}
function key(value) {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{12,100}$/.test(value)) throw error('A valid request reference is required');
  return value;
}
function receipt(value) {
  if (typeof value !== 'string') throw error('Attach a payment screenshot');
  const match = /^data:image\/(jpeg|png);base64,([a-zA-Z0-9+/=]+)$/.exec(value);
  if (!match) throw error('Attach a JPG or PNG screenshot');
  const bytes = Buffer.from(match[2], 'base64');
  const valid = match[1] === 'jpeg' ? bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 :
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (!valid || bytes.length < 16 || bytes.length > 768 * 1024) throw error('Screenshot must be a JPG or PNG below 768 KB');
  return value;
}
const route = fn => async (req, res, next) => { try { await fn(req, res); } catch (e) { next(e); } };
router.get('/settings', route(async (_, res) => {
  const setting = await Settings.findOne({ key: 'walletPayment' }).lean();
  res.json(setting?.value || { payeeName: '', phone: '', upiId: '' });
}));
router.post('/settings', route(async (req, res) => {
  adminOnly(req);
  const value = Object.fromEntries(['payeeName', 'phone', 'upiId'].map(k => [k, `${req.body[k] || ''}`.trim()]));
  if (!value.payeeName || value.payeeName.length > 80 || (value.phone && !/^\d{10}$/.test(value.phone)) ||
      (value.upiId && !/^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$/.test(value.upiId)) || (!value.phone && !value.upiId)) {
    throw error('Enter the recipient name and a valid phone number or UPI ID');
  }
  await Settings.updateOne({ key: 'walletPayment' }, { value, updatedBy: req.user.username }, { upsert: true });
  res.json(value);
}));
router.get('/', route(async (req, res) => {
  const name = username(req);
  const [account, entries, payments] = await Promise.all([
    Account.findOne({ username: name }).lean(), Entry.find({ username: name }).sort({ createdAt: -1 }).limit(50).lean(),
    Payment.find({ username: name }).sort({ createdAt: -1 }).limit(50).lean(),
  ]);
  res.json({ ...snapshot(account), entries, payments });
}));
router.get('/admin', route(async (req, res) => {
  adminOnly(req);
  const [users, accounts, payments, pendingCount] = await Promise.all([
    User.find({ role: { $ne: 'ADMIN' }, deletedAt: null }).select('username role').sort({ username: 1 }).lean(),
    Account.find().lean(), Payment.find({ status: 'pending' }).sort({ createdAt: 1 }).limit(100).lean(),
    Payment.countDocuments({ status: 'pending' }),
  ]);
  res.json({ users: users.map(u => ({ ...u, ...snapshot(accounts.find(a => a.username === u.username)) })),
    payments, pendingCount, pushConfigured: await credentialConfigured() });
}));
router.post('/notification-credentials', route(async (req, res) => {
  adminOnly(req);
  await configureCredential(req.body.account, req.user.username);
  res.json({ ok: true });
  void deliverPendingNotifications();
}));
router.post('/credit', route(async (req, res) => {
  adminOnly(req);
  const account = await adminCredit(`${req.body.username || ''}`.trim().toLowerCase(), req.body.amount,
    req.user.username, key(req.body.requestId));
  res.json(snapshot(account));
}));
router.post('/payments', route(async (req, res) => {
  if (req.walletUser.role === 'ADMIN') throw error('Submit a payment from a customer or agent account');
  const amountPaise = money(req.body.amount, 20000);
  const requestKey = key(req.body.requestId);
  const utr = `${req.body.utr || ''}`.replace(/\s/g, '').toUpperCase();
  if (!/^[A-Z0-9]{6,40}$/.test(utr)) throw error('Enter the UTR / transaction reference');
  const image = receipt(req.body.receipt);
  const setting = await Settings.findOne({ key: 'walletPayment' }).lean();
  if (!setting?.value?.phone && !setting?.value?.upiId) throw error('Payment details have not been configured');
  let payment;
  try {
    payment = await Payment.create({ username: req.user.username, amountPaise, utr, receipt: image, idempotencyKey: requestKey });
  } catch (e) {
    if (e.code !== 11000) throw e;
    payment = await Payment.findOne({ $or: [{ utr }, { username: req.user.username, idempotencyKey: requestKey }] });
    if (!payment || payment.username !== req.user.username || payment.utr !== utr || payment.amountPaise !== amountPaise) {
      throw error('This transaction reference has already been submitted', 409);
    }
  }
  void deliverPendingNotifications();
  res.status(201).json({ id: payment._id, status: payment.status });
}));
router.get('/payments/:id/receipt', route(async (req, res) => {
  const payment = await Payment.findById(req.params.id).select('+receipt').lean();
  if (!payment) throw error('Payment not found', 404);
  if (payment.username !== req.user.username) adminOnly(req);
  res.json({ receipt: payment.receipt });
}));
router.post('/payments/:id/review', route(async (req, res) => {
  adminOnly(req);
  const payment = await reviewPayment(req.params.id, req.user.username, req.body.action, req.body.note);
  res.json({ id: payment._id, status: payment.status });
}));
router.post('/device', route(async (req, res) => {
  adminOnly(req);
  const token = req.body.token;
  if (typeof token !== 'string' || token.length < 30 || token.length > 4096) throw error('Invalid notification registration');
  await Device.updateOne({ token }, { username: req.user.username }, { upsert: true });
  void deliverPendingNotifications();
  res.json({ ok: true });
}));
router.post('/device/remove', route(async (req, res) => {
  await Device.deleteOne({ token: req.body.token, username: req.user.username });
  res.json({ ok: true });
}));
router.post('/device/test', route(async (req, res) => {
  adminOnly(req);
  const device = await Device.findOne({ username: req.user.username,
    ...(req.body.token ? { token: req.body.token } : {}) }).select('+token').sort({ updatedAt: -1 });
  if (!device) throw error('Open the admin app and allow notifications first', 409);
  const sender = await messaging();
  if (!sender) throw error('Server notifications have not been configured', 503);
  await sender.send({ token: device.token,
    notification: { title: 'My Result', body: 'Notification test successful.' },
    data: { type: 'wallet_test' }, android: { priority: 'high', notification: {
      channelId: 'wallet_payments', tag: 'wallet-notification-test', icon: 'ic_notification', sound: 'default',
    } } });
  res.json({ accepted: true });
}));
router.use((e, req, res, next) => {
  if (res.headersSent) return next(e);
  res.status(e.status || 500).json({ error: e.status ? e.message : 'Wallet request failed. Please retry.', code: e.code });
});
module.exports = router;
