import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/shared/providers/settings_controller.dart';

@pragma('vm:entry-point')
Future<void> reminderAlarmCallback(
  int alarmId,
  Map<String, dynamic> params,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await ReminderNotificationService.instance.handleAlarmFired(alarmId, params);
}

@pragma('vm:entry-point')
void _handleNotificationResponse(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  unawaited(
    ReminderNotificationService.instance.handleNotificationResponse(response),
  );
}

@pragma('vm:entry-point')
void reminderNotificationBackgroundResponse(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  unawaited(
    ReminderNotificationService.instance.handleNotificationResponse(response),
  );
}

class ReminderNotificationService {
  ReminderNotificationService._();

  static final ReminderNotificationService instance =
      ReminderNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _callbacksRegistered = false;
  Future<void>? _alarmManagerInitialization;
  Future<void> _speechQueue = Future<void>.value();

  static const String _channelId = 'lifeease_reminders_v2';
  static const String _channelName = 'Reminder Alerts';
  static const String _channelDescription =
      'Alerts for scheduled LifeEase reminders.';
  static const String _doneActionId = 'mark_done';
  static const String _stopActionId = 'stop_repeating';
  static const String _repeatConfigPrefix = 'lifeease.reminder.repeat.';
  static const String _scheduledIdsKey = 'lifeease.reminder.scheduled_ids';

  Future<void> initialize({bool requestPermissions = true}) async {
    if (_initialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    await _ensureSettingsLoaded();
    await _ensureAlarmManagerInitialized();

    if (!_callbacksRegistered) {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            reminderNotificationBackgroundResponse,
      );
      _callbacksRegistered = true;
    }

    await _createNotificationChannel();
    if (requestPermissions) {
      await _requestPermissions();
    }
    _initialized = true;
  }

  Future<void> scheduleReminder(Map<String, dynamic> reminder) async {
    await initialize();

    final id = reminder['id']?.toString();
    if (!SettingsController.instance.notificationsEnabled) {
      if (id != null && id.isNotEmpty) {
        await _cancelAlarmById(_notificationIdFor(id));
      }
      return;
    }
    if (reminder['isCompleted'] == true || reminder['is_completed'] == true) {
      await cancelReminder(id);
      return;
    }

    final title = reminder['title']?.toString().trim();
    final scheduledAt = _dateTimeFromValue(
      reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
    );
    final isRepeating =
        reminder['isRepeating'] == true ||
        reminder['is_repeating'] == true ||
        (reminder['repeat_type']?.toString() ?? '').toLowerCase() != 'none';
    final repeatIntervalMinutes = _repeatIntervalMinutes(reminder);

    if (id == null || id.isEmpty || title == null || title.isEmpty) return;
    if (scheduledAt == null) return;

    final notificationTime = _notificationTimeFor(
      scheduledAt,
      isRepeating: isRepeating,
      repeatIntervalMinutes: repeatIntervalMinutes,
    );
    if (!notificationTime.isAfter(DateTime.now())) {
      debugPrint('Reminder scheduling skipped: computed time is in the past.');
      return;
    }

    final notificationId = _notificationIdFor(id);
    final canScheduleExactAlarms = await _canScheduleExactAlarms();
    if (!canScheduleExactAlarms) {
      debugPrint(
        'Exact alarm permission is not granted; attempting to schedule anyway.',
      );
    }

    await _cancelAlarmById(notificationId, removeTracking: false);

    final params = _alarmParamsFor(reminder);
    final scheduled = await _scheduleAlarm(
      notificationTime: notificationTime,
      alarmId: notificationId,
      params: params,
    );
    var usedAlarmManager = scheduled;

    if (!scheduled) {
      debugPrint(
        'Alarm manager scheduling failed for "$title" at '
        '${notificationTime.toIso8601String()}.',
      );
      final fallbackScheduled = await _scheduleLocalNotification(
        notificationTime: notificationTime,
        alarmId: notificationId,
        reminder: params,
      );
      if (!fallbackScheduled) {
        debugPrint(
          'Reminder fallback scheduling failed for "$title" at '
          '${notificationTime.toIso8601String()}.',
        );
        return;
      }
      usedAlarmManager = false;
    }

    await _addScheduledId(notificationId);
    if (isRepeating && usedAlarmManager) {
      await _saveRepeatConfig(notificationId, params);
    } else {
      await _removeRepeatConfig(notificationId);
    }
  }

  Future<void> schedulePendingReminders(
    List<Map<String, dynamic>> reminders,
  ) async {
    await initialize();

    if (!SettingsController.instance.notificationsEnabled) {
      await _cancelTrackedAlarms();
      return;
    }

    await _cancelTrackedAlarms();
    for (final reminder in reminders) {
      await scheduleReminder(reminder);
    }
  }

  Future<void> cancelReminder(String? reminderId) async {
    await initialize();
    if (reminderId == null || reminderId.isEmpty) return;
    final notificationId = _notificationIdFor(reminderId);
    await AndroidAlarmManager.cancel(notificationId);
    await _plugin.cancel(id: notificationId);
    await _removeScheduledId(notificationId);
    await _removeRepeatConfig(notificationId);
  }

  Future<void> cancelAll() async {
    await initialize();
    await _cancelTrackedAlarms();
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();

      final canScheduleExact = await android?.canScheduleExactNotifications();
      if (canScheduleExact == false) {
        await android?.requestExactAlarmsPermission();
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> _createNotificationChannel() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await android.createNotificationChannel(channel);
  }

  NotificationDetails _details() {
    final settings = SettingsController.instance;
    final android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: settings.soundEnabled,
      enableVibration: settings.vibrationEnabled,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      actions: [
        AndroidNotificationAction(
          _doneActionId,
          TtsLanguageService.doneActionLabel(),
          titleColor: const Color(0xFF2E7D32),
          cancelNotification: true,
          semanticAction: SemanticAction.markAsRead,
        ),
        AndroidNotificationAction(
          _stopActionId,
          TtsLanguageService.stopReminderActionLabel(),
          titleColor: const Color(0xFFD32F2F),
          cancelNotification: true,
          semanticAction: SemanticAction.delete,
        ),
      ],
    );

    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: settings.soundEnabled,
    );

    return NotificationDetails(android: android, iOS: ios);
  }

  DateTime _notificationTimeFor(
    DateTime scheduledAt, {
    required bool isRepeating,
    required int repeatIntervalMinutes,
  }) {
    final leadTime = _leadDuration(
      SettingsController.instance.reminderLeadTime,
    );
    var notificationTime = scheduledAt.subtract(leadTime);

    if (isRepeating && repeatIntervalMinutes >= 0) {
      final interval = _repeatIntervalDuration(repeatIntervalMinutes);
      while (!notificationTime.isAfter(DateTime.now())) {
        notificationTime = notificationTime.add(interval);
        scheduledAt = scheduledAt.add(interval);
      }
    }

    if (notificationTime.isAfter(DateTime.now())) return notificationTime;
    return scheduledAt;
  }

  Duration _leadDuration(String value) {
    final normalized = value.toLowerCase().trim();
    final number = int.tryParse(RegExp(r'\d+').stringMatch(normalized) ?? '');

    if (number == null || number <= 0) return Duration.zero;
    if (normalized.contains('hour')) return Duration(hours: number);
    return Duration(minutes: number);
  }

  String _bodyFor(Map<String, dynamic> reminder, DateTime scheduledAt) {
    final title =
        reminder['title']?.toString() ?? TtsLanguageService.reminderLabel();
    final description = reminder['description']?.toString().trim() ?? '';
    if (description.isNotEmpty) {
      return '$title\n${TtsLanguageService.descriptionLabel()}: $description';
    }
    return title;
  }

  String _spokenTextFor(Map<String, dynamic> reminder) {
    final reminderLabel = TtsLanguageService.reminderLabel();
    final descriptionLabel = TtsLanguageService.descriptionLabel();
    final title = reminder['title']?.toString().trim() ?? '';
    final description = reminder['description']?.toString().trim() ?? '';

    if (description.isEmpty) {
      return '$reminderLabel: $title.';
    }

    return '$reminderLabel: $title. $descriptionLabel: $description.';
  }

  Map<String, dynamic> _alarmParamsFor(Map<String, dynamic> reminder) {
    return <String, dynamic>{
      'id': reminder['id']?.toString(),
      'title': reminder['title']?.toString(),
      'description': reminder['description']?.toString(),
      'reminder_time': reminder['reminder_time']?.toString(),
      'scheduledTimeMillis': reminder['scheduledTimeMillis'],
      'category': reminder['category']?.toString(),
      'repeat_type': reminder['repeat_type']?.toString(),
      'isRepeating':
          reminder['isRepeating'] == true || reminder['is_repeating'] == true,
      'repeatIntervalMinutes': _repeatIntervalMinutes(reminder),
      'priority': reminder['priority']?.toString(),
      'language': reminder['language']?.toString(),
    };
  }

  int _repeatIntervalMinutes(Map<String, dynamic> reminder) {
    final directValue = reminder['repeatIntervalMinutes'];
    if (directValue is int && directValue > 0) return directValue;
    if (directValue is String) {
      final parsed = int.tryParse(directValue);
      if (parsed != null && parsed > 0) return parsed;
    }

    final repeatType = reminder['repeat_type']?.toString().toLowerCase();
    final customRepeat = _customRepeatMinutes(repeatType);
    if (customRepeat != null) return customRepeat;

    switch (repeatType) {
      case 'hourly':
        return 60;
      case 'daily':
        return 1440;
      case 'weekly':
        return 10080;
      case 'monthly':
        return 43200;
      default:
        return 0;
    }
  }

  Future<void> handleAlarmFired(
    int alarmId,
    Map<String, dynamic> params,
  ) async {
    await initialize(requestPermissions: false);

    final reminder = Map<String, dynamic>.from(params);
    final scheduledAt = _dateTimeFromValue(
      reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
    );
    if (scheduledAt == null) return;

    final isRepeating =
        reminder['isRepeating'] == true ||
        reminder['is_repeating'] == true ||
        (reminder['repeat_type']?.toString() ?? '').toLowerCase() != 'none';
    final repeatIntervalMinutes = _repeatIntervalMinutes(reminder);

    try {
      await _showReminderNotification(alarmId, reminder, scheduledAt);
    } catch (error, stackTrace) {
      debugPrint('Reminder notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (isRepeating && repeatIntervalMinutes >= 0) {
      final interval = _repeatIntervalDuration(repeatIntervalMinutes);
      final nextScheduledAt = scheduledAt.add(interval);
      final nextNotificationTime = _notificationTimeFor(
        nextScheduledAt,
        isRepeating: true,
        repeatIntervalMinutes: repeatIntervalMinutes,
      );

      final nextReminder = Map<String, dynamic>.from(reminder)
        ..['reminder_time'] = nextScheduledAt.toIso8601String()
        ..['scheduledTimeMillis'] = nextScheduledAt.millisecondsSinceEpoch;

      await _saveRepeatConfig(alarmId, nextReminder);
      final scheduled = await _scheduleAlarm(
        notificationTime: nextNotificationTime,
        alarmId: alarmId,
        params: nextReminder,
      );
      if (!scheduled) {
        debugPrint(
          'Repeating reminder reschedule failed for alarm $alarmId at '
          '${nextNotificationTime.toIso8601String()}.',
        );
      }
    } else {
      await _removeScheduledId(alarmId);
      await _removeRepeatConfig(alarmId);
    }

    try {
      if (SettingsController.instance.soundEnabled) {
        await _speakReminder(reminder);
      }
    } catch (error, stackTrace) {
      debugPrint('Reminder speech failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    await initialize(requestPermissions: false);

    if (response.actionId != _stopActionId &&
        response.actionId != _doneActionId) {
      return;
    }

    final payload = _payloadFrom(response.payload);
    if (payload == null) return;

    if (response.actionId == _doneActionId && payload.reminderId.isNotEmpty) {
      await ReminderRepository().markReminderCompleteById(payload.reminderId);
    }
    if (response.actionId == _stopActionId && payload.reminderId.isNotEmpty) {
      await ReminderRepository().markReminderCanceledById(payload.reminderId);
    }

    await _cancelAlarmById(payload.alarmId);
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

  Future<void> _showReminderNotification(
    int alarmId,
    Map<String, dynamic> reminder,
    DateTime scheduledAt,
  ) async {
    await _plugin.show(
      id: alarmId,
      title: TtsLanguageService.notificationTitle(),
      body: _bodyFor(reminder, scheduledAt),
      notificationDetails: _details(),
      payload: _payloadFor(alarmId, reminder),
    );
  }

  Future<void> _speakReminder(Map<String, dynamic> reminder) {
    final text = _spokenTextFor(reminder);
    return _enqueueSpeech(() async {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await TtsLanguageService.applyCurrentLanguage(_tts);
      await _tts.stop();
      await _tts.speak(text);
    });
  }

  Future<void> _enqueueSpeech(Future<void> Function() action) {
    _speechQueue = _speechQueue.then((_) => action()).catchError((
      error,
      stackTrace,
    ) {
      debugPrint('Reminder speech queue failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    });
    return _speechQueue;
  }

  Future<void> _saveRepeatConfig(
    int alarmId,
    Map<String, dynamic> reminder,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_repeatConfigKey(alarmId), jsonEncode(reminder));
  }

  Future<void> _removeRepeatConfig(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_repeatConfigKey(alarmId));
  }

  Future<void> _clearRepeatConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_repeatConfigPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _addScheduledId(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    final alarmIdString = alarmId.toString();
    if (!ids.contains(alarmIdString)) {
      ids.add(alarmIdString);
      await prefs.setStringList(_scheduledIdsKey, ids);
    }
  }

  Future<void> _removeScheduledId(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    final alarmIdString = alarmId.toString();
    if (ids.remove(alarmIdString)) {
      await prefs.setStringList(_scheduledIdsKey, ids);
    }
  }

  Future<void> _cancelAlarmById(
    int alarmId, {
    bool removeTracking = true,
  }) async {
    await AndroidAlarmManager.cancel(alarmId);
    await _plugin.cancel(id: alarmId);
    if (removeTracking) {
      await _removeScheduledId(alarmId);
      await _removeRepeatConfig(alarmId);
    }
  }

  Future<bool> _scheduleAlarm({
    required DateTime notificationTime,
    required int alarmId,
    required Map<String, dynamic> params,
  }) async {
    try {
      return await AndroidAlarmManager.oneShotAt(
        notificationTime,
        alarmId,
        reminderAlarmCallback,
        allowWhileIdle: true,
        wakeup: true,
        rescheduleOnReboot: true,
        params: params,
      );
    } catch (error, stackTrace) {
      debugPrint('Reminder alarm scheduling threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _cancelTrackedAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    for (final id in ids) {
      final alarmId = int.tryParse(id);
      if (alarmId == null) continue;
      await AndroidAlarmManager.cancel(alarmId);
      await _plugin.cancel(id: alarmId);
    }
    await prefs.remove(_scheduledIdsKey);
    await _clearRepeatConfigs();
  }

  String _repeatConfigKey(int alarmId) => '$_repeatConfigPrefix$alarmId';

  Duration _repeatIntervalDuration(int repeatIntervalMinutes) {
    if (repeatIntervalMinutes == 0) return const Duration(seconds: 30);
    return Duration(minutes: repeatIntervalMinutes);
  }

  int? _customRepeatMinutes(String? repeatType) {
    if (repeatType == null) return null;
    final match = RegExp(r'^custom:(\d+)$').firstMatch(repeatType);
    if (match == null) return null;
    final minutes = int.tryParse(match.group(1)!);
    if (minutes == null || minutes < 0) return null;
    return minutes;
  }

  Future<bool> _scheduleLocalNotification({
    required DateTime notificationTime,
    required int alarmId,
    required Map<String, dynamic> reminder,
  }) async {
    try {
      final scheduledAt = _dateTimeFromValue(
        reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
      );
      await _plugin.zonedSchedule(
        id: alarmId,
        title: TtsLanguageService.notificationTitle(),
        body: _bodyFor(reminder, scheduledAt ?? notificationTime),
        scheduledDate: tz.TZDateTime.from(notificationTime, tz.local),
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: _payloadFor(alarmId, reminder),
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('Reminder fallback scheduling threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _ensureAlarmManagerInitialized() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _alarmManagerInitialization ??= AndroidAlarmManager.initialize().then((
      initialized,
    ) {
      if (!initialized) {
        debugPrint('Android alarm manager initialization returned false.');
      }
    });

    await _alarmManagerInitialization;
  }

  Future<bool> _canScheduleExactAlarms() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<void> _ensureSettingsLoaded() async {
    try {
      SettingsController.instance;
    } catch (_) {
      await SettingsController.load();
    }
  }

  String _payloadFor(int alarmId, Map<String, dynamic> reminder) {
    return jsonEncode({
      'alarmId': alarmId,
      'reminderId': reminder['id']?.toString() ?? '',
    });
  }

  _NotificationPayload? _payloadFrom(String? rawPayload) {
    final payload = rawPayload?.trim();
    if (payload == null || payload.isEmpty) return null;

    final legacyAlarmId = int.tryParse(payload);
    if (legacyAlarmId != null) {
      return _NotificationPayload(alarmId: legacyAlarmId, reminderId: '');
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;

      final alarmId = decoded['alarmId'];
      final parsedAlarmId = alarmId is int
          ? alarmId
          : int.tryParse(alarmId?.toString() ?? '');
      if (parsedAlarmId == null) return null;

      return _NotificationPayload(
        alarmId: parsedAlarmId,
        reminderId: decoded['reminderId']?.toString() ?? '',
      );
    } catch (error) {
      debugPrint('Reminder notification payload parse failed: $error');
      return null;
    }
  }

  int _notificationIdFor(String id) {
    var hash = 0;
    for (final codeUnit in id.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

class _NotificationPayload {
  const _NotificationPayload({required this.alarmId, required this.reminderId});

  final int alarmId;
  final String reminderId;
}
