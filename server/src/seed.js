require('dotenv').config();
const bcrypt = require('bcryptjs');
const { connectDb, disconnectDb } = require('./config/db');
const User = require('./models/User');

async function seed() {
  await connectDb();
  const username = 'admin';
  const existing = await User.findOne({ username });
  if (existing) {
    console.log('Admin user already exists');
  } else {
    const passwordHash = await bcrypt.hash('1234', 10);
    await User.create({
      username,
      passwordHash,
      role: 'ADMIN',
      isBlocked: false,
    });
    console.log('Seeded admin / 1234');
  }
  await disconnectDb();
}

seed().catch(async (e) => {
  console.error(e);
  try {
    await disconnectDb();
  } catch (_) {}
  process.exit(1);
});
