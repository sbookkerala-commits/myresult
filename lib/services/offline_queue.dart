import '../database/local_database.dart';

enum QueueOp { booking, bookingDelete, sale, result, settings, users }

class OfflineQueue {
  static Future<void> enqueue(QueueOp op, Map<String, dynamic> payload) async {
    await LocalDatabase.enqueueSync(op.name, payload);
  }

  static Future<List<Map<String, dynamic>>> drain() async {
    return LocalDatabase.drainSyncQueue();
  }

  static Future<int> pendingCount() async {
    return LocalDatabase.syncQueueCount();
  }
}
