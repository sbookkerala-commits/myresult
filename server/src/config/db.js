const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');
const { logInfo, logWarn, logError, logMemory } = require('../utils/logger');

let memoryServer = null;
let listenersAttached = false;

const embeddedDataDir = path.join(__dirname, '../../.mongo-data');

function attachConnectionListeners() {
  if (listenersAttached) return;
  listenersAttached = true;

  mongoose.connection.on('connected', () => {
    logInfo('MongoDB connected', {
      readyState: mongoose.connection.readyState,
      host: mongoose.connection.host,
      name: mongoose.connection.name,
    });
    logMemory('memory after MongoDB connect');
  });

  mongoose.connection.on('disconnected', () => {
    logWarn('MongoDB disconnected — mongoose will attempt auto-reconnect');
  });

  mongoose.connection.on('reconnected', () => {
    logInfo('MongoDB reconnected');
  });

  mongoose.connection.on('error', (err) => {
    logError('MongoDB connection error', err);
  });
}

async function connectDb() {
  mongoose.set('strictQuery', true);
  attachConnectionListeners();

  const uri = process.env.MONGODB_URI;
  const useEmbedded =
    process.env.USE_EMBEDDED_MONGO === 'true' ||
    process.env.USE_EMBEDDED_MONGO === '1';

  const connectOptions = {
    maxPoolSize: parseInt(process.env.MONGO_MAX_POOL || '5', 10),
    minPoolSize: 0,
    serverSelectionTimeoutMS: 15000,
    socketTimeoutMS: 45000,
    heartbeatFrequencyMS: 10000,
    // Keep memory low on Render free/starter
    maxIdleTimeMS: 30000,
  };

  if (useEmbedded) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('USE_EMBEDDED_MONGO must not be enabled in production');
    }
    fs.mkdirSync(embeddedDataDir, { recursive: true });
    const { MongoMemoryReplSet } = require('mongodb-memory-server');
    memoryServer = await MongoMemoryReplSet.create({
      replSet: { count: 1, storageEngine: 'wiredTiger' },
      instanceOpts: [{
        dbPath: embeddedDataDir,
      }],
    });
    const embeddedUri = memoryServer.getUri();
    await mongoose.connect(embeddedUri, connectOptions);
    logInfo('Using embedded MongoDB (local dev only)', {
      dataFolder: embeddedDataDir,
    });
    return;
  }

  if (!uri) {
    throw new Error(
      'MONGODB_URI is required. Set Atlas connection string and USE_EMBEDDED_MONGO=false'
    );
  }

  await mongoose.connect(uri, connectOptions);
  logInfo('MongoDB Atlas connected');
}

async function disconnectDb() {
  try {
    await mongoose.disconnect();
    logInfo('MongoDB disconnected cleanly');
  } catch (err) {
    logError('MongoDB disconnect failed', err);
  }
  if (memoryServer) {
    try {
      await memoryServer.stop();
    } catch (err) {
      logError('Embedded MongoDB stop failed', err);
    }
    memoryServer = null;
  }
}

function isDbReady() {
  return mongoose.connection.readyState === 1;
}

module.exports = { connectDb, disconnectDb, isDbReady };
