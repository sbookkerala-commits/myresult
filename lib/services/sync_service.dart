import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/local_database.dart';
import 'api_service.dart';
import 'offline_queue.dart';

/// Cloud sync: local SQLite first, then API. Offline → SQLite queue.
class SyncService {
  static const _tokenKey = 'api_jwt_token';
  static const _userKey = 'api_user_json';

  static bool isOnline = false;
  static bool isRestoring = false;
  static final ValueNotifier<bool> restoring = ValueNotifier(false);

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    ApiService.setToken(p.getString(_tokenKey));
    isOnline = await ApiService.healthCheck();

    Connectivity().onConnectivityChanged.listen((results) async {
      final connected = results.any((r) => r != ConnectivityResult.none);
      if (connected) {
        isOnline = await ApiService.healthCheck();
        if (isOnline && ApiService.token != null) await flushQueue();
      } else {
        isOnline = false;
      }
    });
  }

  static Future<void> saveSession({
    required String token,
    required String username,
    required String role,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tokenKey, token);
    await p.setString(
      _userKey,
      jsonEncode({'username': username, 'role': role}),
    );
    ApiService.setToken(token);
  }

  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_tokenKey);
    await p.remove(_userKey);
    ApiService.setToken(null);
  }

  static Future<Map<String, dynamic>?> cachedSession() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_userKey);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  /// After login — restore all data from MongoDB.
  static Future<Map<String, dynamic>> restoreFromCloud() async {
    isRestoring = true;
    restoring.value = true;
    try {
      isOnline = await ApiService.healthCheck();
      if (!isOnline) {
        throw ApiException('No connection to server');
      }
      return await ApiService.restore();
    } finally {
      isRestoring = false;
      restoring.value = false;
    }
  }

  static Future<bool> _canSync() async {
    isOnline = await ApiService.healthCheck();
    return isOnline && ApiService.token != null;
  }

  static Future<void> syncBooking(Map<String, dynamic> billJson) async {
    final billNo = billJson['billNo'];
    if (!await _canSync()) {
      await OfflineQueue.enqueue(QueueOp.booking, billJson);
      debugPrint('Booking queued offline: billNo=$billNo');
      return;
    }
    try {
      final statusCode = await ApiService.postBooking(billJson);
      debugPrint(
        'Booking POST cloud statusCode=$statusCode billNo=$billNo',
      );
    } catch (e) {
      debugPrint('Booking POST cloud failed billNo=$billNo: $e');
      await OfflineQueue.enqueue(QueueOp.booking, billJson);
    }
  }

  static Future<void> queueBooking(Map<String, dynamic> billJson) async {
    await syncBooking(billJson);
  }

  static Future<void> queueBookingDelete(int billNo) async {
    await OfflineQueue.enqueue(QueueOp.bookingDelete, {'billNo': billNo});
    await flushQueue();
  }

  static Future<void> queueSale(Map<String, dynamic> saleJson) async {
    await OfflineQueue.enqueue(QueueOp.sale, saleJson);
    await flushQueue();
  }

  static Future<void> queueResult(Map<String, dynamic> resultJson) async {
    await OfflineQueue.enqueue(QueueOp.result, resultJson);
    await flushQueue();
  }

  static Future<void> queueUsers(List<Map<String, dynamic>> users) async {
    await OfflineQueue.enqueue(QueueOp.users, {'users': users});
    await flushQueue();
  }

  static Future<void> flushQueue() async {
    if (!await _canSync()) return;

    final pending = await OfflineQueue.drain();
    if (pending.isEmpty) return;

    final failed = <Map<String, dynamic>>[];

    for (final item in pending) {
      try {
        final op = item['op']?.toString() ?? '';
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        switch (op) {
          case 'booking':
            final statusCode = await ApiService.postBooking(payload);
            debugPrint(
              'Queue booking POST statusCode=$statusCode billNo=${payload['billNo']}',
            );
            break;
          case 'bookingDelete':
            final rawNo = payload['billNo'];
            final billNo = rawNo is int ? rawNo : int.parse(rawNo.toString());
            await ApiService.deleteBooking(billNo);
            break;
          case 'sale':
            await ApiService.postSale(payload);
            break;
          case 'result':
            await ApiService.postResult(payload);
            break;
          case 'settings':
            await ApiService.postSettings(
              key: payload['key'] as String,
              value: payload['value'],
            );
            break;
          case 'users':
            final users = (payload['users'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            await ApiService.syncUsers(users);
            break;
        }
      } catch (e) {
        debugPrint('Sync queue item failed: $e');
        failed.add(item);
      }
    }

    if (failed.isNotEmpty) {
      for (final f in failed) {
        await LocalDatabase.reEnqueueSync(
          f['op'] as String,
          Map<String, dynamic>.from(f['payload'] as Map),
        );
      }
      debugPrint('Sync queue re-queued ${failed.length} failed item(s)');
    }
  }
}
