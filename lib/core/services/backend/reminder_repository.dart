import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifeease/core/services/supabase_config.dart';
import 'offline_sync_service.dart';

class ReminderRepository {
  final OfflineSyncService _offline;

  ReminderRepository({OfflineSyncService? offline})
    : _offline = offline ?? OfflineSyncService();

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  Future<void> saveReminder(Map<String, dynamic> reminder) async {
    await _offline.saveReminder(reminder);

    final client = _client;
    if (client == null) return;
    try {
      await client.from('reminders').upsert(_remoteReminder(reminder, client));
    } catch (_) {
      await _offline.saveReminder({...reminder, 'sync_status': 'queued'});
    }
  }

  Future<List<Map<String, dynamic>>> loadReminders() async {
    final client = _client;
    if (client == null) return _offline.loadReminders();
    try {
      final rows = await client
          .from('reminders')
          .select()
          .order('reminder_time', ascending: true);
      return rows
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return _offline.loadReminders();
    }
  }

  Future<void> deleteReminder(String id) async {
    await _offline.deleteReminder(id);

    final client = _client;
    if (client == null || id.length != 36) return;
    try {
      await client.from('reminders').delete().eq('id', id);
    } catch (_) {
      await _offline.saveReminder({
        'id': id,
        'sync_status': 'delete_queued',
        'deleted_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> markReminderComplete(Map<String, dynamic> reminder) async {
    final id = reminder['id']?.toString();
    if (id == null) return;

    final updated = {
      ...reminder,
      'is_completed': true,
      'isCompleted': true,
      'sync_status': 'queued',
    };
    await _offline.updateReminder(id, updated);

    final client = _client;
    if (client == null || id.length != 36) return;
    try {
      await client
          .from('reminders')
          .update({'is_completed': true, 'sync_status': 'synced'})
          .eq('id', id);
    } catch (_) {
      await _offline.updateReminder(id, updated);
    }
  }

  Stream<List<Map<String, dynamic>>> watchReminders() {
    final client = _client;
    if (client == null) return const Stream.empty();
    return client
        .from('reminders')
        .stream(primaryKey: ['id'])
        .order('reminder_time')
        .map(
          (rows) => rows
              .map<Map<String, dynamic>>(
                (row) => Map<String, dynamic>.from(row),
              )
              .toList(),
        );
  }

  Future<void> syncQueuedReminders() async {
    final client = _client;
    if (client == null) return;
    final reminders = await _offline.loadReminders();
    for (final reminder in reminders) {
      try {
        if (reminder['sync_status'] == 'delete_queued') {
          final id = reminder['id']?.toString();
          if (id != null && id.length == 36) {
            await client.from('reminders').delete().eq('id', id);
            await _offline.deleteReminder(id);
          }
          continue;
        }
        if (reminder['sync_status'] != 'queued') continue;
        await client
            .from('reminders')
            .upsert(
              _remoteReminder({...reminder, 'sync_status': 'synced'}, client),
            );
        await _offline.updateReminder(reminder['id'].toString(), {...reminder, 'sync_status': 'synced'});
      } catch (e) {
        // Skip on individual failure to prevent loop halt
      }
    }
  }

  Map<String, dynamic> _remoteReminder(
    Map<String, dynamic> reminder,
    SupabaseClient client,
  ) {
    final userId = client.auth.currentUser?.id;
    final id = reminder['id']?.toString();
    return {
      if (id != null && id.length == 36) 'id': id,
      if (userId != null) 'user_id': userId,
      'title': reminder['title'],
      'description': reminder['description'],
      'reminder_time': reminder['reminder_time'],
      'repeat_type': reminder['repeat_type'] ?? 'none',
      'priority': reminder['priority'] ?? 'normal',
      'category': reminder['category'] ?? 'general',
      'is_completed': reminder['is_completed'] ?? false,
      'language': reminder['language'] ?? 'en',
      'sync_status': reminder['sync_status'] ?? 'synced',
    };
  }
}
