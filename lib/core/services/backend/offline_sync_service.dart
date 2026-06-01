import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineSyncService {
  static const String dbName = 'lifeease_offline.db';
  static const String remindersTable = 'offline_reminders';
  static const String voiceQueueTable = 'queued_voice_commands';
  static const String adherenceHistoryTable = 'reminder_adherence_history';

  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), dbName);
    _db = await openDatabase(
      path,
      version: 2,
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
        await _createAdherenceHistoryTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createAdherenceHistoryTable(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createAdherenceHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $adherenceHistoryTable (
        id TEXT PRIMARY KEY,
        reminder_id TEXT,
        date_key TEXT,
        scheduled_at INTEGER,
        status TEXT,
        data TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_adherence_date '
      'ON $adherenceHistoryTable(date_key)',
    );
  }

  Future<void> saveReminder(Map<String, dynamic> reminder) async {
    final db = await _getDb();
    final id = reminder['id']?.toString() ?? DateTime.now().toIso8601String();
    await db.insert(remindersTable, {
      'id': id,
      'data': jsonEncode(reminder),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> saveAdherenceEntry(Map<String, dynamic> entry) async {
    final db = await _getDb();
    final id = entry['id']?.toString();
    if (id == null || id.isEmpty) return;
    await db.insert(adherenceHistoryTable, {
      'id': id,
      'reminder_id': entry['reminder_id']?.toString(),
      'date_key': entry['date_key']?.toString(),
      'scheduled_at': entry['scheduled_at'],
      'status': entry['status']?.toString(),
      'data': jsonEncode(entry),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> loadAdherenceHistory({
    String? startDateKey,
    String? endDateKey,
  }) async {
    final db = await _getDb();
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (startDateKey != null) {
      whereParts.add('date_key >= ?');
      whereArgs.add(startDateKey);
    }
    if (endDateKey != null) {
      whereParts.add('date_key <= ?');
      whereArgs.add(endDateKey);
    }
    final rows = await db.query(
      adherenceHistoryTable,
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'scheduled_at ASC',
    );
    return rows.map((row) {
      final dataStr = row['data'] as String;
      return Map<String, dynamic>.from(jsonDecode(dataStr));
    }).toList();
  }

  Future<void> queueVoiceCommand(Map<String, dynamic> payload) async {
    final db = await _getDb();
    final data = {...payload, 'queued_at': DateTime.now().toIso8601String()};
    await db.insert(voiceQueueTable, {'data': jsonEncode(data)});
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
