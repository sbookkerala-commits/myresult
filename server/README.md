# MyResult — Express + MongoDB Atlas API

## Quick start

```bash
cd server
copy .env.example .env
# Set MONGODB_URI and JWT_SECRET in .env
npm install
npm run seed
npm run dev
```

## API endpoints

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | No |
| POST | `/api/auth/login` | No |
| GET/POST | `/api/users` | JWT + Admin/Agent |
| GET/POST | `/api/bookings` | JWT |
| DELETE | `/api/bookings/:billNo` | JWT (soft delete) |
| GET/POST | `/api/sales` | JWT |
| GET/POST | `/api/results` | JWT |
| GET/POST | `/api/pending` | JWT |
| GET | `/api/chart-archive` | JWT |
| GET/POST | `/api/settings` | JWT (price list: Admin) |
| GET | `/api/sync/restore` | JWT |
| POST | `/api/backup` | JWT + Admin |

## Data rules

- **21-day retention:** bookings, sales, results, pending
- **Chart archive:** permanent, never auto-deleted
- **Daily backup:** 2:00 AM cron → `server/backups/`
- **Passwords:** bcrypt hashed
- **Roles:** ADMIN, AGENT, SUBAGENT, CUSTOMER

## Flutter

- Local cache: **SQLite** (`lib/database/local_database.dart`)
- API config: `lib/config/api_config.dart`
- No Firebase dependencies
