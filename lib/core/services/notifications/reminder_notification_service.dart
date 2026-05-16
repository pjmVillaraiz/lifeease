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
  static const String _skipActionId = 'skip_occurrence';
  static const String _darwinEnglishCategoryId = 'lifeease_reminder_actions_en';
  static const String _darwinTagalogCategoryId = 'lifeease_reminder_actions_tl';
  static const String _repeatConfigPrefix = 'lifeease.reminder.repeat.';
  static const String _scheduledIdsKey = 'lifeease.reminder.scheduled_ids';
  static const Duration _lateReminderGrace = Duration(minutes: 5);
  static const Duration _ignoredRetryDelay = Duration(minutes: 1);
  static const int _maxIgnoredRetries = 3;

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
      final iosSettings = DarwinInitializationSettings(
        notificationCategories: _darwinReminderCategories(),
      );
      final settings = InitializationSettings(
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
    if (_isCompleted(reminder) ||
        _isCanceled(reminder) ||
        _isSkipped(reminder) ||
        _isMissed(reminder)) {
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

    final notificationId = _notificationIdFor(id);
    final params = _alarmParamsFor(reminder);
    final now = DateTime.now();
    if (_shouldFireImmediately(scheduledAt, now)) {
      debugPrint(
        'Reminder "$title" is slightly late; firing immediately instead of '
        'skipping.',
      );
      await _cancelAlarmById(notificationId, removeTracking: false);
      await handleAlarmFired(notificationId, params);
      return;
    }

    final notificationTime = _notificationTimeFor(
      scheduledAt,
      isRepeating: isRepeating,
      repeatIntervalMinutes: repeatIntervalMinutes,
    );
    if (!notificationTime.isAfter(now)) {
      if (!isRepeating) {
        debugPrint(
          'Reminder "$title" was missed outside the '
          '${_lateReminderGrace.inMinutes}-minute grace window.',
        );
        await ReminderRepository().markReminderMissed(reminder);
        await cancelReminder(id);
        return;
      }

      debugPrint(
        'Repeating reminder "$title" computed a past notification time; '
        'marking this occurrence missed before the next occurrence.',
      );
      final repository = ReminderRepository();
      await repository.markReminderMissed(reminder);
      final updated = await repository.loadReminderById(id);
      if (updated != null) {
        await scheduleReminder(updated);
      }
      return;
    }

    final canScheduleExactAlarms = await _canScheduleExactAlarms();
    if (!canScheduleExactAlarms) {
      debugPrint(
        'Exact alarm permission is not granted; attempting to schedule anyway.',
      );
    }

    await _cancelAlarmById(notificationId, removeTracking: false);

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
          _skipActionId,
          TtsLanguageService.skipActionLabel(),
          titleColor: const Color(0xFF1565C0),
          cancelNotification: true,
        ),
      ],
    );

    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: settings.soundEnabled,
      categoryIdentifier: _currentDarwinCategoryId(),
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

  bool _shouldFireImmediately(DateTime scheduledAt, DateTime now) {
    if (scheduledAt.isAfter(now)) return false;
    return now.difference(scheduledAt) <= _lateReminderGrace;
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
    final title = reminder['title']?.toString().trim() ?? '';
    final description = reminder['description']?.toString().trim() ?? '';
    return TtsLanguageService.reminderSpeech(title, description);
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
      'retryCount': reminder['retryCount'] is int
          ? reminder['retryCount']
          : int.tryParse(reminder['retryCount']?.toString() ?? '') ?? 0,
      'markMissedOnFire': reminder['markMissedOnFire'] == true,
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

  Future<void> handleAlarmFired(
    int alarmId,
    Map<String, dynamic> params,
  ) async {
    await initialize(requestPermissions: false);

    final reminder = Map<String, dynamic>.from(params);
    final id = reminder['id']?.toString();
    if (id != null && id.isNotEmpty) {
      final latestReminder = await ReminderRepository().loadReminderById(id);
      if (latestReminder != null &&
          (_isCompleted(latestReminder) ||
              _isCanceled(latestReminder) ||
              _isSkipped(latestReminder) ||
              _isMissed(latestReminder))) {
        debugPrint(
          'Reminder alarm $alarmId ignored because reminder $id is already '
          'completed, skipped, cancelled, or missed.',
        );
        await _cancelAlarmById(alarmId);
        return;
      }
    }

    final scheduledAt = _dateTimeFromValue(
      reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
    );
    if (scheduledAt == null) return;

    if (reminder['markMissedOnFire'] == true) {
      await _markReminderMissedIfStillPending(alarmId, reminder);
      return;
    }

    try {
      await _showReminderNotification(alarmId, reminder, scheduledAt);
    } catch (error, stackTrace) {
      debugPrint('Reminder notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    await _scheduleIgnoredRetryOrMiss(alarmId: alarmId, reminder: reminder);

    try {
      await _speakReminder(reminder);
    } catch (error, stackTrace) {
      debugPrint('Reminder speech failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    await initialize(requestPermissions: false);

    if (response.actionId != _skipActionId &&
        response.actionId != _doneActionId) {
      return;
    }

    final payload = _payloadFrom(response.payload);
    if (payload == null) {
      debugPrint(
        'Reminder notification action ignored: missing payload for '
        '${response.actionId}.',
      );
      return;
    }

    await _applyNotificationAction(
      actionId: response.actionId,
      payload: payload,
    );
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

  Future<void> _applyNotificationAction({
    required String? actionId,
    required _NotificationPayload payload,
  }) async {
    try {
      debugPrint(
        'Reminder notification action received: $actionId '
        'alarm=${payload.alarmId} reminder=${payload.reminderId}.',
      );

      await _cancelActionAlarms(payload);
      await _tts.stop();

      if (payload.reminderId.isEmpty) {
        debugPrint(
          'Reminder notification action could only cancel alarm '
          '${payload.alarmId}; reminder id was missing.',
        );
        return;
      }

      final repository = ReminderRepository();
      if (actionId == _doneActionId) {
        await repository.markReminderCompleteById(payload.reminderId);
        await _rescheduleRepeatingReminder(payload.reminderId);
        debugPrint('Reminder ${payload.reminderId} marked completed.');
        return;
      }

      if (actionId == _skipActionId) {
        await repository.markReminderSkippedById(payload.reminderId);
        await _rescheduleRepeatingReminder(payload.reminderId);
        debugPrint('Reminder ${payload.reminderId} skipped for now.');
        return;
      }
    } catch (error, stackTrace) {
      debugPrint('Reminder notification action failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _scheduleIgnoredRetryOrMiss({
    required int alarmId,
    required Map<String, dynamic> reminder,
  }) async {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return;

    final retryCount = reminder['retryCount'] is int
        ? reminder['retryCount'] as int
        : int.tryParse(reminder['retryCount']?.toString() ?? '') ?? 0;
    final nextReminder = Map<String, dynamic>.from(reminder);
    if (retryCount < _maxIgnoredRetries) {
      nextReminder
        ..['retryCount'] = retryCount + 1
        ..['markMissedOnFire'] = false;
    } else {
      nextReminder
        ..['retryCount'] = retryCount
        ..['markMissedOnFire'] = true;
    }

    final scheduled = await _scheduleAlarm(
      notificationTime: DateTime.now().add(_ignoredRetryDelay),
      alarmId: alarmId,
      params: nextReminder,
    );
    if (!scheduled) {
      debugPrint('Ignored reminder retry scheduling failed for $id.');
      return;
    }
    await _addScheduledId(alarmId);
  }

  Future<void> _markReminderMissedIfStillPending(
    int alarmId,
    Map<String, dynamic> reminder,
  ) async {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return;

    final repository = ReminderRepository();
    final latestReminder = await repository.loadReminderById(id);
    if (latestReminder != null &&
        (_isCompleted(latestReminder) ||
            _isCanceled(latestReminder) ||
            _isSkipped(latestReminder) ||
            _isMissed(latestReminder))) {
      await _cancelAlarmById(alarmId);
      return;
    }

    await repository.markReminderMissedById(id);
    await _plugin.cancel(id: alarmId);
    await _removeScheduledId(alarmId);
    await _removeRepeatConfig(alarmId);
    await _rescheduleRepeatingReminder(id);
    debugPrint('Reminder $id marked missed after ignored retries.');
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

  Future<void> _cancelActionAlarms(_NotificationPayload payload) async {
    final alarmIds = <int>{payload.alarmId};
    if (payload.reminderId.isNotEmpty) {
      alarmIds.add(_notificationIdFor(payload.reminderId));
    }

    for (final alarmId in alarmIds) {
      await _cancelAlarmById(alarmId);
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

  bool _isCompleted(Map<String, dynamic> reminder) {
    return reminder['isCompleted'] == true || reminder['is_completed'] == true;
  }

  bool _isCanceled(Map<String, dynamic> reminder) {
    return reminder['isCanceled'] == true ||
        reminder['is_canceled'] == true ||
        reminder['sync_status'] == 'canceled' ||
        reminder['sync_status'] == 'cancelled' ||
        reminder['task_status'] == 'cancelled';
  }

  bool _isSkipped(Map<String, dynamic> reminder) {
    return reminder['task_status'] == 'skipped' && !_isRepeating(reminder);
  }

  bool _isMissed(Map<String, dynamic> reminder) {
    return reminder['task_status'] == 'missed' && !_isRepeating(reminder);
  }

  Future<void> _rescheduleRepeatingReminder(String reminderId) async {
    final reminder = await ReminderRepository().loadReminderById(reminderId);
    if (reminder == null || !_isRepeating(reminder)) return;
    if (_isCompleted(reminder) || _isCanceled(reminder)) return;

    debugPrint(
      'Rescheduling next occurrence for repeating reminder $reminderId.',
    );
    await scheduleReminder(reminder);
  }

  bool _isRepeating(Map<String, dynamic> reminder) {
    final repeatType = reminder['repeat_type']?.toString().toLowerCase();
    return reminder['isRepeating'] == true ||
        reminder['is_repeating'] == true ||
        (repeatType != null && repeatType.isNotEmpty && repeatType != 'none');
  }

  List<DarwinNotificationCategory> _darwinReminderCategories() {
    return [
      _darwinReminderCategory(
        identifier: _darwinEnglishCategoryId,
        doneLabel: 'Done',
        skipLabel: 'Skip',
      ),
      _darwinReminderCategory(
        identifier: _darwinTagalogCategoryId,
        doneLabel: 'Tapos',
        skipLabel: 'Laktawan',
      ),
    ];
  }

  DarwinNotificationCategory _darwinReminderCategory({
    required String identifier,
    required String doneLabel,
    required String skipLabel,
  }) {
    return DarwinNotificationCategory(
      identifier,
      actions: [
        DarwinNotificationAction.plain(_doneActionId, doneLabel),
        DarwinNotificationAction.plain(_skipActionId, skipLabel),
      ],
    );
  }

  String _currentDarwinCategoryId() {
    return TtsLanguageService.currentLanguage == AppSpeechLanguage.tagalog
        ? _darwinTagalogCategoryId
        : _darwinEnglishCategoryId;
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
