const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');

let memoryServer = null;

const embeddedDataDir = path.join(__dirname, '../../.mongo-data');

async function connectDb() {
  mongoose.set('strictQuery', true);

  const uri = process.env.MONGODB_URI;
  const useEmbedded =
    process.env.USE_EMBEDDED_MONGO === 'true' ||
    process.env.USE_EMBEDDED_MONGO === '1';

  if (useEmbedded) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('USE_EMBEDDED_MONGO must not be enabled in production');
    }
    fs.mkdirSync(embeddedDataDir, { recursive: true });
    const { MongoMemoryServer } = require('mongodb-memory-server');
    memoryServer = await MongoMemoryServer.create({
      instance: {
        dbPath: embeddedDataDir,
        storageEngine: 'wiredTiger',
      },
    });
    const embeddedUri = memoryServer.getUri();
    await mongoose.connect(embeddedUri);
    console.log('Using embedded MongoDB (local dev only)');
    console.log('Data folder:', embeddedDataDir);
    return;
  }

  if (!uri) {
    throw new Error(
      'MONGODB_URI is required. Set Atlas connection string and USE_EMBEDDED_MONGO=false'
    );
  }

  await mongoose.connect(uri);
  console.log('MongoDB Atlas connected');
}

async function disconnectDb() {
  await mongoose.disconnect();
  if (memoryServer) {
    await memoryServer.stop();
    memoryServer = null;
  }
}

module.exports = { connectDb, disconnectDb };
