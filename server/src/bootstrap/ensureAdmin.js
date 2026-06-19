const bcrypt = require('bcryptjs');
const User = require('../models/User');

async function ensureAdminUser() {
  const username = 'admin';
  const existing = await User.findOne({ username });
  if (existing) return;

  const passwordHash = await bcrypt.hash('1234', 10);
  await User.create({
    username,
    passwordHash,
    role: 'ADMIN',
    isBlocked: false,
  });
  console.log('Created default admin user (admin / 1234)');
}

module.exports = { ensureAdminUser };
