import 'package:hive_flutter/hive_flutter.dart';

class OfflineSyncService {
  static const String remindersBox = 'offline_reminders';
  static const String voiceQueueBox = 'queued_voice_commands';

  Future<Box> _open(String name) => Hive.openBox(name);

  Future<void> saveReminder(Map<String, dynamic> reminder) async {
    final box = await _open(remindersBox);
    final key = reminder['id']?.toString() ?? DateTime.now().toIso8601String();
    await box.put(key, reminder);
  }

  Future<void> deleteReminder(String id) async {
    final box = await _open(remindersBox);
    await box.delete(id);
  }

  Future<void> updateReminder(String id, Map<String, dynamic> reminder) async {
    final box = await _open(remindersBox);
    await box.put(id, reminder);
  }

  Future<List<Map<String, dynamic>>> loadReminders() async {
    final box = await _open(remindersBox);
    return box.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> queueVoiceCommand(Map<String, dynamic> payload) async {
    final box = await _open(voiceQueueBox);
    await box.add({...payload, 'queued_at': DateTime.now().toIso8601String()});
  }

  Future<List<Map<String, dynamic>>> loadQueuedVoiceCommands() async {
    final box = await _open(voiceQueueBox);
    return box.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> clearQueuedVoiceCommands() async {
    final box = await _open(voiceQueueBox);
    await box.clear();
  }
}
