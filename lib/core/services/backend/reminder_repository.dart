import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifeease/core/services/supabase_config.dart';
import 'offline_sync_service.dart';

class ReminderRepository {
  final OfflineSyncService _offline;
  static final StreamController<void> _changes =
      StreamController<void>.broadcast();
  static List<Map<String, dynamic>>? _memoryCache;
  static DateTime? _lastRemoteRefresh;
  static bool _remoteRefreshRunning = false;

  ReminderRepository({OfflineSyncService? offline})
    : _offline = offline ?? OfflineSyncService();

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  static Stream<void> get changes => _changes.stream;

  static void notifyChanged() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  Future<void> saveReminder(Map<String, dynamic> reminder) async {
    await _offline.saveReminder(reminder);
    _upsertMemoryCache(reminder);
    notifyChanged();

    final client = _client;
    if (client == null) return;
    try {
      await client.from('reminders').upsert(_remoteReminder(reminder, client));
    } catch (_) {
      await _offline.saveReminder({...reminder, 'sync_status': 'queued'});
    }
  }

  Future<List<Map<String, dynamic>>> loadReminders() async {
    final localReminders = await _offline.loadReminders();
    final activeLocal = _activeReminders(localReminders);
    if (activeLocal.isNotEmpty) {
      _memoryCache = activeLocal;
      _refreshRemoteInBackground(activeLocal);
      return activeLocal;
    }

    if (_memoryCache != null) {
      _refreshRemoteInBackground(_memoryCache!);
      return _memoryCache!;
    }

    final client = _client;
    if (client == null) return activeLocal;
    try {
      final rows = await client
          .from('reminders')
          .select()
          .order('reminder_time', ascending: true);
      final remoteReminders = rows
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList();
      final merged = _mergeRemoteAndLocal(remoteReminders, localReminders);
      _memoryCache = merged;
      for (final reminder in merged) {
        await _offline.saveReminder(reminder);
      }
      return merged;
    } catch (_) {
      return activeLocal;
    }
  }

  Future<Map<String, dynamic>?> loadReminderById(String id) async {
    final reminders = await loadReminders();
    for (final reminder in reminders) {
      if (reminder['id']?.toString() == id) {
        return reminder;
      }
    }
    return null;
  }

  Future<void> deleteReminder(String id) async {
    await _offline.deleteReminder(id);
    _memoryCache?.removeWhere((reminder) => reminder['id']?.toString() == id);
    notifyChanged();

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

    if (_isRepeating(reminder)) {
      await _markRepeatingOccurrence(reminder, 'completed');
      return;
    }

    final updated = {
      ...reminder,
      'is_completed': true,
      'isCompleted': true,
      'is_canceled': false,
      'isCanceled': false,
      'sync_status': 'queued',
      'completed_at': DateTime.now().toIso8601String(),
    };
    await _offline.saveReminder(updated);
    notifyChanged();

    final client = _client;
    if (client == null || id.length != 36) return;
    try {
      await client
          .from('reminders')
          .update({'is_completed': true, 'sync_status': 'synced'})
          .eq('id', id);
      await _offline.saveReminder({...updated, 'sync_status': 'synced'});
      notifyChanged();
    } catch (_) {
      await _offline.saveReminder(updated);
    }
  }

  Future<void> markReminderCompleteById(String id) async {
    final reminders = await loadReminders();
    final existing = reminders.cast<Map<String, dynamic>?>().firstWhere(
      (reminder) => reminder?['id']?.toString() == id,
      orElse: () => null,
    );

    await markReminderComplete(existing ?? {'id': id});
  }

  Future<void> markReminderCanceled(Map<String, dynamic> reminder) async {
    final id = reminder['id']?.toString();
    if (id == null) return;

    final updated = {
      ...reminder,
      'is_completed': false,
      'isCompleted': false,
      'is_canceled': true,
      'isCanceled': true,
      'sync_status': 'canceled',
      'task_status': 'cancelled',
      'canceled_at': DateTime.now().toIso8601String(),
    };
    await _offline.saveReminder(updated);
    notifyChanged();

    final client = _client;
    if (client == null || id.length != 36) return;
    try {
      await client
          .from('reminders')
          .update({'sync_status': 'canceled'})
          .eq('id', id);
      await _offline.saveReminder(updated);
      notifyChanged();
    } catch (_) {
      await _offline.saveReminder(updated);
    }
  }

  Future<void> markReminderCanceledById(String id) async {
    final reminders = await loadReminders();
    final existing = reminders.cast<Map<String, dynamic>?>().firstWhere(
      (reminder) => reminder?['id']?.toString() == id,
      orElse: () => null,
    );

    await markReminderCanceled(existing ?? {'id': id});
  }

  Future<void> markReminderSkipped(Map<String, dynamic> reminder) async {
    final id = reminder['id']?.toString();
    if (id == null) return;

    if (_isRepeating(reminder)) {
      await _markRepeatingOccurrence(reminder, 'skipped');
      return;
    }

    final updated = {
      ...reminder,
      'is_completed': false,
      'isCompleted': false,
      'is_canceled': false,
      'isCanceled': false,
      'task_status': 'skipped',
      'last_occurrence_status': 'skipped',
      'last_occurrence_date': _dateKey(DateTime.now()),
      'last_occurrence_at': DateTime.now().toIso8601String(),
      'skipped_at': DateTime.now().toIso8601String(),
      'sync_status': 'queued',
    };
    await _offline.saveReminder(updated);
    notifyChanged();

    final client = _client;
    if (client == null || id.length != 36) return;
    try {
      await client
          .from('reminders')
          .upsert(
            _remoteReminder({...updated, 'sync_status': 'synced'}, client),
          );
      await _offline.saveReminder({...updated, 'sync_status': 'synced'});
      notifyChanged();
    } catch (_) {
      await _offline.saveReminder(updated);
    }
  }

  Future<void> markReminderSkippedById(String id) async {
    final reminders = await loadReminders();
    final existing = reminders.cast<Map<String, dynamic>?>().firstWhere(
      (reminder) => reminder?['id']?.toString() == id,
      orElse: () => null,
    );

    await markReminderSkipped(existing ?? {'id': id});
  }

  Future<void> markReminderMissed(Map<String, dynamic> reminder) async {
    final id = reminder['id']?.toString();
    if (id == null) return;

    if (_isRepeating(reminder)) {
      await _markRepeatingOccurrence(reminder, 'missed');
      return;
    }

    final updated = {
      ...reminder,
      'is_completed': false,
      'isCompleted': false,
      'is_canceled': false,
      'isCanceled': false,
      'task_status': 'missed',
      'last_occurrence_status': 'missed',
      'last_occurrence_date': _dateKey(DateTime.now()),
      'last_occurrence_at': DateTime.now().toIso8601String(),
      'missed_at': DateTime.now().toIso8601String(),
      'sync_status': 'queued',
    };
    await _offline.saveReminder(updated);
    notifyChanged();

    final client = _client;
    if (client == null || id.length != 36) return;
    try {
      await client
          .from('reminders')
          .upsert(
            _remoteReminder({...updated, 'sync_status': 'synced'}, client),
          );
      await _offline.saveReminder({...updated, 'sync_status': 'synced'});
      notifyChanged();
    } catch (_) {
      await _offline.saveReminder(updated);
    }
  }

  Future<void> markReminderMissedById(String id) async {
    final reminders = await loadReminders();
    final existing = reminders.cast<Map<String, dynamic>?>().firstWhere(
      (reminder) => reminder?['id']?.toString() == id,
      orElse: () => null,
    );

    await markReminderMissed(existing ?? {'id': id});
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
        if (_isCancelled(reminder)) {
          final id = reminder['id']?.toString();
          if (id != null && id.length == 36) {
            await client
                .from('reminders')
                .update({'sync_status': 'canceled'})
                .eq('id', id);
          }
          continue;
        }
        if (reminder['sync_status'] != 'queued') continue;
        await client
            .from('reminders')
            .upsert(
              _remoteReminder({...reminder, 'sync_status': 'synced'}, client),
            );
        await _offline.updateReminder(reminder['id'].toString(), {
          ...reminder,
          'sync_status': 'synced',
        });
      } catch (error) {
        debugPrint('Reminder sync skipped for ${reminder['id']}: $error');
      }
    }
  }

  void _refreshRemoteInBackground(List<Map<String, dynamic>> localReminders) {
    final client = _client;
    if (client == null || _remoteRefreshRunning) return;
    final lastRefresh = _lastRemoteRefresh;
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < const Duration(seconds: 20)) {
      return;
    }

    _remoteRefreshRunning = true;
    unawaited(
      _refreshRemote(client, localReminders).whenComplete(() {
        _remoteRefreshRunning = false;
        _lastRemoteRefresh = DateTime.now();
      }),
    );
  }

  Future<void> _refreshRemote(
    SupabaseClient client,
    List<Map<String, dynamic>> localReminders,
  ) async {
    try {
      final rows = await client
          .from('reminders')
          .select()
          .order('reminder_time', ascending: true);
      final remoteReminders = rows
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList();
      final merged = _mergeRemoteAndLocal(remoteReminders, localReminders);
      _memoryCache = merged;
      for (final reminder in merged) {
        await _offline.saveReminder(reminder);
      }
      notifyChanged();
    } catch (error) {
      debugPrint('Reminder background refresh skipped: $error');
    }
  }

  void _upsertMemoryCache(Map<String, dynamic> reminder) {
    final id = reminder['id']?.toString();
    if (id == null) return;
    final cache = [...?_memoryCache];
    final index = cache.indexWhere((item) => item['id']?.toString() == id);
    if (index == -1) {
      cache.add(reminder);
    } else {
      cache[index] = reminder;
    }
    _memoryCache = _activeReminders(cache);
  }

  List<Map<String, dynamic>> _mergeRemoteAndLocal(
    List<Map<String, dynamic>> remoteReminders,
    List<Map<String, dynamic>> localReminders,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final reminder in remoteReminders) {
      final id = reminder['id']?.toString();
      if (id != null) {
        merged[id] = reminder;
      }
    }

    for (final reminder in localReminders) {
      final id = reminder['id']?.toString();
      if (id == null) continue;
      final syncStatus = reminder['sync_status']?.toString();
      if (syncStatus == 'delete_queued') {
        merged.remove(id);
        continue;
      }
      if (syncStatus == 'queued' ||
          syncStatus == 'canceled' ||
          syncStatus == 'cancelled' ||
          reminder['task_status'] == 'cancelled' ||
          reminder['task_status'] == 'skipped' ||
          reminder['task_status'] == 'missed' ||
          reminder['last_occurrence_status'] != null ||
          reminder['is_completed'] == true ||
          reminder['isCompleted'] == true ||
          reminder['is_canceled'] == true ||
          reminder['isCanceled'] == true) {
        merged[id] = reminder;
      } else {
        merged.putIfAbsent(id, () => reminder);
      }
    }

    return _activeReminders(merged.values.toList());
  }

  List<Map<String, dynamic>> _activeReminders(
    List<Map<String, dynamic>> reminders,
  ) {
    return reminders
        .where((reminder) => reminder['sync_status'] != 'delete_queued')
        .toList();
  }

  bool _isCancelled(Map<String, dynamic> reminder) {
    return reminder['sync_status'] == 'canceled' ||
        reminder['sync_status'] == 'cancelled' ||
        reminder['task_status'] == 'cancelled' ||
        reminder['is_canceled'] == true ||
        reminder['isCanceled'] == true;
  }

  Future<void> _markRepeatingOccurrence(
    Map<String, dynamic> reminder,
    String status,
  ) async {
    final id = reminder['id']?.toString();
    if (id == null) return;

    final nextScheduledAt = _nextOccurrenceAfterNow(reminder);
    final updated = {
      ...reminder,
      'is_completed': false,
      'isCompleted': false,
      'is_canceled': false,
      'isCanceled': false,
      'task_status': 'active',
      'last_occurrence_status': status,
      'last_occurrence_date': _dateKey(DateTime.now()),
      'last_occurrence_at': DateTime.now().toIso8601String(),
      if (status == 'completed')
        'completed_at': DateTime.now().toIso8601String(),
      if (status == 'skipped') 'skipped_at': DateTime.now().toIso8601String(),
      if (status == 'missed') 'missed_at': DateTime.now().toIso8601String(),
      if (nextScheduledAt != null)
        'reminder_time': nextScheduledAt.toIso8601String(),
      if (nextScheduledAt != null)
        'scheduledTimeMillis': nextScheduledAt.millisecondsSinceEpoch,
      'sync_status': 'queued',
    };

    await _offline.saveReminder(updated);
    notifyChanged();

    final client = _client;
    if (client == null || id.length != 36) return;
    try {
      await client
          .from('reminders')
          .upsert(
            _remoteReminder({...updated, 'sync_status': 'synced'}, client),
          );
      await _offline.saveReminder({...updated, 'sync_status': 'synced'});
      notifyChanged();
    } catch (error) {
      debugPrint('Repeating reminder occurrence sync queued for $id: $error');
      await _offline.saveReminder(updated);
    }
  }

  DateTime? _nextOccurrenceAfterNow(Map<String, dynamic> reminder) {
    final scheduledAt = _dateTimeFromValue(
      reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
    );
    if (scheduledAt == null) return null;

    final interval = _repeatIntervalDuration(_repeatIntervalMinutes(reminder));
    var next = scheduledAt.add(interval);
    final now = DateTime.now();
    while (!next.isAfter(now)) {
      next = next.add(interval);
    }
    return next;
  }

  bool _isRepeating(Map<String, dynamic> reminder) {
    final repeatType = reminder['repeat_type']?.toString().toLowerCase();
    return reminder['isRepeating'] == true ||
        reminder['is_repeating'] == true ||
        (repeatType != null && repeatType.isNotEmpty && repeatType != 'none');
  }

  int _repeatIntervalMinutes(Map<String, dynamic> reminder) {
    final directValue = reminder['repeatIntervalMinutes'];
    if (directValue is int && directValue > 0) return directValue;
    if (directValue is String) {
      final parsed = int.tryParse(directValue);
      if (parsed != null && parsed > 0) return parsed;
    }

    final repeatType = reminder['repeat_type']?.toString().toLowerCase();
    final customMatch = RegExp(r'^custom:(\d+)$').firstMatch(repeatType ?? '');
    if (customMatch != null) {
      final minutes = int.tryParse(customMatch.group(1)!);
      if (minutes != null && minutes >= 0) return minutes;
    }

    switch (repeatType) {
      case 'hourly':
        return 60;
      case 'daily':
        return 1440;
      case 'twice_monthly':
        return 21600;
      case 'weekly':
        return 10080;
      case 'monthly':
        return 43200;
      default:
        return 0;
    }
  }

  Duration _repeatIntervalDuration(int repeatIntervalMinutes) {
    if (repeatIntervalMinutes == 0) return const Duration(seconds: 30);
    return Duration(minutes: repeatIntervalMinutes);
  }

  DateTime? _dateTimeFromValue(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;

      final millis = int.tryParse(value);
      if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
      'task_status': reminder['task_status'] ?? 'active',
    };
  }
}
