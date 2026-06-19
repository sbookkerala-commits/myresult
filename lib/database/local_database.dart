import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite cache — primary offline storage on mobile/desktop.
class LocalDatabase {
  static Database? _db;
  static bool _migrated = false;

  static Future<void> ensureReady() async {
    if (kIsWeb) return;
    await _open();
    await _migrateFromSharedPreferencesOnce();
  }

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'myresult.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE kv_store (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            op TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> _migrateFromSharedPreferencesOnce() async {
    if (_migrated || kIsWeb) return;
    _migrated = true;
    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'db_sales',
      'db_users',
      'db_results',
      'db_bills',
      'app_sales_v1',
      'app_users_v1',
      'app_bills_v1',
      'app_results_v1',
      'offline_sync_queue_v1',
    ];
    for (final key in keys) {
      final existing = await getString(key);
      if (existing != null && existing.isNotEmpty) continue;
      final legacy = prefs.getString(key);
      if (legacy != null && legacy.isNotEmpty) {
        await setString(key, legacy);
      }
    }
  }

  static Future<String?> getString(String key) async {
    if (kIsWeb) return null;
    final db = await _open();
    final rows = await db.query(
      'kv_store',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  static Future<void> setString(String key, String value) async {
    if (kIsWeb) return;
    final db = await _open();
    await db.insert(
      'kv_store',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> enqueueSync(String op, Map<String, dynamic> payload) async {
    if (kIsWeb) return;
    final db = await _open();
    await db.insert('sync_queue', {
      'op': op,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> drainSyncQueue() async {
    if (kIsWeb) return [];
    final db = await _open();
    final rows = await db.query('sync_queue', orderBy: 'id ASC');
    await db.delete('sync_queue');
    return rows.map((r) {
      return {
        'op': r['op'],
        'payload': jsonDecode(r['payload'] as String) as Map<String, dynamic>,
      };
    }).toList();
  }

  static Future<int> syncQueueCount() async {
    if (kIsWeb) return 0;
    final db = await _open();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_queue');
    return (r.first['c'] as int?) ?? 0;
  }

  static Future<void> reEnqueueSync(String op, Map<String, dynamic> payload) async {
    await enqueueSync(op, payload);
  }
}
