import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineSyncService {
  static const String dbName = 'lifeease_offline.db';
  static const String remindersTable = 'offline_reminders';
  static const String voiceQueueTable = 'queued_voice_commands';

  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), dbName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $remindersTable (
            id TEXT PRIMARY KEY,
            data TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE $voiceQueueTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> saveReminder(Map<String, dynamic> reminder) async {
    final db = await _getDb();
    final id = reminder['id']?.toString() ?? DateTime.now().toIso8601String();
    await db.insert(
      remindersTable,
      {'id': id, 'data': jsonEncode(reminder)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteReminder(String id) async {
    final db = await _getDb();
    await db.delete(remindersTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateReminder(String id, Map<String, dynamic> reminder) async {
    final db = await _getDb();
    await db.update(
      remindersTable,
      {'data': jsonEncode(reminder)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> loadReminders() async {
    final db = await _getDb();
    final rows = await db.query(remindersTable);
    return rows.map((row) {
      final dataStr = row['data'] as String;
      return Map<String, dynamic>.from(jsonDecode(dataStr));
    }).toList();
  }

  Future<void> queueVoiceCommand(Map<String, dynamic> payload) async {
    final db = await _getDb();
    final data = {...payload, 'queued_at': DateTime.now().toIso8601String()};
    await db.insert(
      voiceQueueTable,
      {'data': jsonEncode(data)},
    );
  }

  Future<List<Map<String, dynamic>>> loadQueuedVoiceCommands() async {
    final db = await _getDb();
    final rows = await db.query(voiceQueueTable);
    return rows.map((row) {
      final dataStr = row['data'] as String;
      return Map<String, dynamic>.from(jsonDecode(dataStr));
    }).toList();
  }

  Future<void> clearQueuedVoiceCommands() async {
    final db = await _getDb();
    await db.delete(voiceQueueTable);
  }
}
