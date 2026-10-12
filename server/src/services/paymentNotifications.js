const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');
const User = require('../models/User');
const WalletPayment = require('../models/WalletPayment');
const Device = require('../models/NotificationDevice');
const Delivery = require('../models/PushDelivery');
const Credential = require('../models/NotificationCredential');
const crypto = require('crypto');
let running = false;
function encryptionKey() {
  if (!process.env.JWT_SECRET) throw new Error('Server encryption secret unavailable');
  return crypto.createHash('sha256').update(`myresult-notifications:${process.env.JWT_SECRET}`).digest();
}
async function configureCredential(account, actor) {
  if (account?.type !== 'service_account' || account.project_id !== 'myresult-sbook-2026' ||
      account.client_email !== 'wallet-notifications@myresult-sbook-2026.iam.gserviceaccount.com' ||
      typeof account.private_key !== 'string' || !account.private_key.includes('BEGIN PRIVATE KEY')) {
    throw Object.assign(new Error('Invalid My Result notification credentials'), { status: 400 });
  }
  // Keep the private key out of app settings, restore payloads, logs and the APK.
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const payload = Buffer.concat([cipher.update(JSON.stringify(account), 'utf8'), cipher.final()]);
  const encrypted = [iv, cipher.getAuthTag(), payload].map(b => b.toString('base64')).join('.');
  await Credential.updateOne({ name: 'firebase' }, { encrypted, projectId: account.project_id,
    updatedBy: actor }, { upsert: true });
  const { deleteApp } = require('firebase-admin/app');
  for (const app of getApps()) await deleteApp(app);
}
async function credentialConfigured() {
  return !!process.env.FIREBASE_SERVICE_ACCOUNT_JSON || !!await Credential.exists({ name: 'firebase' });
}
async function messaging() {
  if (!getApps().length) {
    let account;
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) account = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    else {
      const stored = await Credential.findOne({ name: 'firebase' }).select('+encrypted').lean();
      if (!stored) return null;
      const [iv, tag, payload] = stored.encrypted.split('.').map(s => Buffer.from(s, 'base64'));
      const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey(), iv);
      decipher.setAuthTag(tag);
      account = JSON.parse(Buffer.concat([decipher.update(payload), decipher.final()]).toString('utf8'));
    }
    initializeApp({ credential: cert(account) });
  }
  return getMessaging();
}
async function deliverPendingNotifications({ sender: testSender } = {}) {
  if (running) return;
  running = true;
  try {
    const sender = testSender || await messaging();
    if (!sender) return;
    const admins = await User.find({ role: 'ADMIN', isBlocked: false, deletedAt: null }).select('username').lean();
    const devices = await Device.find({ username: { $in: admins.map(u => u.username) } }).select('+token').limit(100).lean();
    const payments = WalletPayment.find({ status: 'pending' }).sort({ createdAt: 1 }).lean().cursor();
    for await (const payment of payments) {
      for (const device of devices) {
        const filter = { paymentId: payment._id, deviceId: device._id };
        await Delivery.updateOne(filter, { $setOnInsert: filter }, { upsert: true });
        const now = new Date();
        const job = await Delivery.findOneAndUpdate({ ...filter, sentAt: null,
          nextAttemptAt: { $lte: now }, $or: [{ leaseUntil: null }, { leaseUntil: { $lt: now } }] },
        { $set: { leaseUntil: new Date(Date.now() + 90000) }, $inc: { attempts: 1 } }, { new: true });
        if (!job) continue;
        // Re-check ownership and payment status just before sending.
        if (!await WalletPayment.exists({ _id: payment._id, status: 'pending' }) ||
            !await User.exists({ username: device.username, role: 'ADMIN', isBlocked: false, deletedAt: null })) {
          await Delivery.updateOne(filter, { sentAt: now, leaseUntil: null });
          continue;
        }
        try {
          await sender.send({ token: device.token,
            notification: { title: 'Payment verification', body: 'A wallet payment is waiting for your review.' },
            data: { type: 'wallet_payment', paymentId: `${payment._id}` },
            android: { priority: 'high', ttl: 86400000, notification: {
              channelId: 'wallet_payments', tag: `wallet-${payment._id}`, sound: 'default',
              icon: 'ic_notification', color: '#1565C0',
            } },
          });
          await Delivery.updateOne(filter, { sentAt: new Date(), leaseUntil: null, lastError: null });
        } catch (e) {
          const code = e.code || 'push-send-failed';
          if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code)) {
            await Device.deleteOne({ _id: device._id });
            await Delivery.updateOne(filter, { sentAt: now, leaseUntil: null, lastError: code });
          } else {
            await Delivery.updateOne(filter, { leaseUntil: null, lastError: code,
              nextAttemptAt: new Date(Date.now() + Math.min(3600000, 30000 * 2 ** Math.min(job.attempts, 6))) });
          }
        }
      }
    }
  } catch (e) {
    console.error('[wallet notification]', e.code || e.name);
  } finally { running = false; }
}
module.exports = { deliverPendingNotifications, messaging, configureCredential, credentialConfigured };
