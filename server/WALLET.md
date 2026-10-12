# Wallet and admin payment notifications

Wallet funds are stored in integer paise in MongoDB, independently of daily
booking limits. Balances carry forward across days. An account starts using
wallet enforcement when an admin adds credit or approves its first payment.
Existing bookings before that activation are not retroactively charged.

New wallet bookings, edits and deletions require a server confirmation. MongoDB
transactions serialize activity per user so concurrent phones cannot overdraw.
Repeated payment approvals and admin credit request references are idempotent.
Edits charge/refund the difference; deletion refunds only funded amounts once.
Payment requests require at least INR 200, a unique UTR, and a JPG/PNG receipt
below 768 KB. A receipt is evidence for manual review, never automatic approval.
Admins must confirm receipt of the money in their bank/UPI account before approval.

## Firebase

Android is registered in project `myresult-sbook-2026`. Use a service account
limited to `roles/firebasecloudmessaging.admin`. No Firebase database, Storage,
Analytics or Auth is used by this feature.

Preferred server configuration: `FIREBASE_SERVICE_ACCOUNT_JSON` environment
variable containing that service account's JSON, managed as a deployment secret.
Alternatively an authenticated active ADMIN can configure the dedicated
`POST /api/wallet/notification-credentials` endpoint with `{account: ...}`. This
stores the credential in the separate NotificationCredential collection,
encrypted with AES-256-GCM and a key derived from the server JWT_SECRET. It is
never included in app settings, cloud restore, API responses, log output, backups,
or the APK. If JWT_SECRET is rotated, reconfigure the encrypted credential;
environment-based credentials do not have that dependency. Keep the original
service-account JSON in private credential storage, outside the repository.

Notifications target registered devices belonging to active admins only.
Pending payments are durable; per-device delivery records retry transient errors
with backoff and a lease. Notifications use high priority and a stable payment tag.
An accepted delivery is not retried; duplicate accepted deliveries after a crash
replace the same tagged notification. Opening the app also refreshes pending
payments. Settings-level Force Stop, disabled notification permission and a phone
without connectivity can delay or prevent push display.

Phone testing must include foreground, Home-button/background, locked screen,
notification tap, payment review, repeated approval, and logout. Do not use Force
Stop when testing normal background delivery. Android notification permission
must be granted once. iOS push credentials/capabilities are not configured by this
Android implementation.

Run server checks with `node --test test/dailyBookingLimit.test.js test/wallet.test.js`.
The tests use a disposable local MongoDB replica set, never real user balances.
