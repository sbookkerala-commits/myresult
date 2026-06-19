@echo off
cd /d "%~dp0server"
if not exist node_modules (
  echo Installing backend dependencies...
  call npm install
)
echo Seeding admin user...
call npm run seed
echo Starting API on http://localhost:3000
node src/index.js
