import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/services/tts/inworld_tts_service.dart';
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

  static final StreamController<ReminderDueEvent> _dueReminderController =
      StreamController<ReminderDueEvent>.broadcast();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FlutterTts _tts = FlutterTts();
  static const MethodChannel _nativeReminderChannel = MethodChannel(
    'lifeease/reminder_native',
  );

  bool _initialized = false;
  bool _callbacksRegistered = false;
  Future<void>? _alarmManagerInitialization;
  Future<void> _speechQueue = Future<void>.value();

  static const String _channelId = 'lifeease_reminders_silent_v1';
  static const String _channelName = 'Reminder Alerts';
  static const String _channelDescription =
      'Alerts for scheduled LifeEase reminders.';
  static const String _doneActionId = 'mark_done';
  static const String _skipActionId = 'skip_occurrence';
  static const String _darwinEnglishCategoryId = 'lifeease_reminder_actions_en';
  static const String _darwinTagalogCategoryId = 'lifeease_reminder_actions_tl';
  static const String _repeatConfigPrefix = 'lifeease.reminder.repeat.';
  static const String _scheduledIdsKey = 'lifeease.reminder.scheduled_ids';
  static const String _lastTimeZoneKey = 'lifeease.reminder.last_timezone';
  static const String _firedOccurrencePrefix =
      'lifeease.reminder.fired_occurrence.';
  static const String _pendingDuePrefix = 'lifeease.reminder.pending_due.';
  static const String _localNotificationScheduledKey =
      'localNotificationScheduled';
  static const Duration _lateReminderGrace = Duration(minutes: 5);
  static const Duration _ignoredRetryDelay = Duration(seconds: 30);
  static const int _maxIgnoredAttempts = 5;

  Future<void> initialize({bool requestPermissions = true}) async {
    if (_initialized) {
      await initializeTimeZone();
      return;
    }

    await initializeTimeZone();
    await ensureSettingsLoaded();
    await ensureAlarmManagerInitialized();

    if (!_callbacksRegistered) {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      final iosSettings = DarwinInitializationSettings(
        notificationCategories: darwinReminderCategories(),
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

    await createNotificationChannel();
    await drainNativeReminderActions();
    if (requestPermissions) {
      await this.requestPermissions();
      await requestReminderReliabilityAccess();
    }
    _initialized = true;
  }

  Future<void> scheduleReminder(Map<String, dynamic> reminder) async {
    await initialize();

    final id = reminder['id']?.toString();
    if (!SettingsController.instance.notificationsEnabled) {
      if (id != null && id.isNotEmpty) {
        await cancelAlarmById(notificationIdFor(id));
      }
      return;
    }
    if (isCompleted(reminder) ||
        isCanceled(reminder) ||
        isSkipped(reminder) ||
        isMissed(reminder)) {
      await cancelReminder(id);
      return;
    }

    final title = reminder['title']?.toString().trim();
    final scheduledAt = dateTimeFromValue(
      reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
    );
    final isRepeating =
        reminder['isRepeating'] == true ||
        reminder['is_repeating'] == true ||
        (reminder['repeat_type']?.toString() ?? '').toLowerCase() != 'none';
    final repeatIntervalMinutes = repeatIntervalMinutes0(reminder);

    if (id == null || id.isEmpty || title == null || title.isEmpty) return;
    if (scheduledAt == null) return;

    final notificationId = notificationIdFor(id);
    final params = alarmParamsFor(reminder);
    final now = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        'Scheduling reminder "$title" for ${scheduledAt.toIso8601String()} '
        '(now ${now.toIso8601String()}).',
      );
    }
    if (!scheduledAt.isAfter(now) &&
        await hasOccurrenceFired(reminder, scheduledAt)) {
      return;
    }

    if (shouldFireImmediately(scheduledAt, now)) {
      debugPrint(
        'Reminder "$title" is slightly late; firing immediately instead of '
        'skipping.',
      );
      await cancelAlarmById(notificationId, removeTracking: false);
      await scheduleNativeSpeechAlarm(
        notificationTime: DateTime.now().add(const Duration(seconds: 1)),
        alarmId: notificationId,
        reminder: params,
      );
      await handleAlarmFired(notificationId, params);
      return;
    }

    final notificationTime = notificationTimeFor(
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

    final canScheduleExactAlarms = await canScheduleExactAlarms0();
    if (!canScheduleExactAlarms) {
      debugPrint(
        'Exact alarm permission is not granted; using local notification '
        'fallback.',
      );
    }

    await cancelAlarmById(notificationId, removeTracking: false);

    final localScheduled = await scheduleLocalNotification(
      notificationTime: notificationTime,
      alarmId: notificationId,
      reminder: params,
      canScheduleExactAlarms: canScheduleExactAlarms,
    );
    if (!localScheduled) {
      debugPrint(
        'Local notification scheduling failed for "$title" at '
        '${notificationTime.toIso8601String()}.',
      );
    }

    final alarmParams = localScheduled
        ? {...params, _localNotificationScheduledKey: true}
        : params;
    final scheduled = canScheduleExactAlarms
        ? await scheduleAlarm(
            notificationTime: notificationTime,
            alarmId: notificationId,
            params: alarmParams,
          )
        : false;
    var usedAlarmManager = scheduled;
    if (scheduled) {
      await scheduleLocalNotification(
        notificationTime: notificationTime,
        alarmId: notificationId,
        reminder: params,
        canScheduleExactAlarms: canScheduleExactAlarms,
      );
    }

    if (!scheduled && !localScheduled) {
      debugPrint(
        'Alarm manager scheduling failed for "$title" at '
        '${notificationTime.toIso8601String()}.',
      );
      final fallbackScheduled = await scheduleLocalNotification(
        notificationTime: notificationTime,
        alarmId: notificationId,
        reminder: params,
        canScheduleExactAlarms: false,
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

    await scheduleNativeSpeechAlarm(
      notificationTime: notificationTime,
      alarmId: notificationId,
      reminder: params,
    );
    await addScheduledId(notificationId);
    if (isRepeating && usedAlarmManager) {
      await saveRepeatConfig(notificationId, alarmParams);
    } else {
      await removeRepeatConfig(notificationId);
    }
  }

  Future<void> schedulePendingReminders(
    List<Map<String, dynamic>> reminders,
  ) async {
    await initialize();
    await reconcileDueReminders(reminders);

    if (!SettingsController.instance.notificationsEnabled) {
      await cancelTrackedAlarms();
      return;
    }

    await cancelTrackedAlarms();
    for (final reminder in reminders) {
      await scheduleReminder(reminder);
    }
  }

  Future<void> cancelReminder(String? reminderId) async {
    await initialize();
    if (reminderId == null || reminderId.isEmpty) return;
    final notificationId = notificationIdFor(reminderId);
    await AndroidAlarmManager.cancel(notificationId);
    await cancelNativeSpeechAlarm(notificationId);
    await _plugin.cancel(id: notificationId);
    await removeScheduledId(notificationId);
    await removeRepeatConfig(notificationId);
  }

  Future<void> cancelAll() async {
    await initialize();
    await cancelTrackedAlarms();
  }

  Future<void> triggerReminderNow(Map<String, dynamic> reminder) async {
    await initialize();
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return;

    final alarmId = notificationIdFor(id);
    await handleAlarmFired(alarmId, alarmParamsFor(reminder));
  }

  Stream<ReminderDueEvent> get dueReminders => _dueReminderController.stream;

  Future<void> requestPermissions() async {
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

  Future<void> requestReminderReliabilityAccess() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _nativeReminderChannel.invokeMethod<void>(
        'requestReminderReliabilityAccess',
      );
    } catch (error) {
      debugPrint('Reminder reliability access request skipped: $error');
    }
  }

  Future<void> drainNativeReminderActions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final actions = await _nativeReminderChannel.invokeListMethod<dynamic>(
        'drainNativeReminderActions',
      );
      if (actions == null || actions.isEmpty) return;

      for (final action in actions) {
        if (action is! Map) continue;
        final actionId = action['actionId']?.toString();
        final alarmId = action['alarmId'] is int
            ? action['alarmId'] as int
            : int.tryParse(action['alarmId']?.toString() ?? '');
        final reminderId = action['reminderId']?.toString() ?? '';
        if (alarmId == null || reminderId.isEmpty) continue;
        if (actionId != _doneActionId && actionId != _skipActionId) continue;

        await applyNotificationAction(
          actionId: actionId,
          payload: _NotificationPayload(
            alarmId: alarmId,
            reminderId: reminderId,
          ),
        );
      }
    } catch (error) {
      debugPrint('Native reminder action drain skipped: $error');
    }
  }

  Future<void> createNotificationChannel() async {
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
      playSound: false,
      enableVibration: true,
      showBadge: true,
    );

    await android.createNotificationChannel(channel);
  }

  NotificationDetails details() {
    final settings = SettingsController.instance;
    final android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: false,
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
      presentSound: false,
      categoryIdentifier: currentDarwinCategoryId(),
    );

    return NotificationDetails(android: android, iOS: ios);
  }

  DateTime notificationTimeFor(
    DateTime scheduledAt, {
    required bool isRepeating,
    required int repeatIntervalMinutes,
  }) {
    final leadTime = leadDuration(
      SettingsController.instance.reminderLeadTime,
    );
    var notificationTime = scheduledAt.subtract(leadTime);

    if (isRepeating && repeatIntervalMinutes >= 0) {
      final interval = repeatIntervalDuration(repeatIntervalMinutes);
      while (!notificationTime.isAfter(DateTime.now())) {
        notificationTime = notificationTime.add(interval);
        scheduledAt = scheduledAt.add(interval);
      }
    }

    if (notificationTime.isAfter(DateTime.now())) return notificationTime;
    return scheduledAt;
  }

  bool shouldFireImmediately(DateTime scheduledAt, DateTime now) {
    if (scheduledAt.isAfter(now)) return false;
    return now.difference(scheduledAt) <= _lateReminderGrace;
  }

  Duration leadDuration(String value) {
    final normalized = value.toLowerCase().trim();
    final number = int.tryParse(RegExp(r'\d+').stringMatch(normalized) ?? '');

    if (number == null || number <= 0) return Duration.zero;
    if (normalized.contains('hour')) return Duration(hours: number);
    return Duration(minutes: number);
  }

  String bodyFor(Map<String, dynamic> reminder, DateTime scheduledAt) {
    final title =
        reminder['title']?.toString() ?? TtsLanguageService.reminderLabel();
    final description = reminder['description']?.toString().trim() ?? '';
    if (description.isNotEmpty) {
      return '$title\n${TtsLanguageService.descriptionLabel()}: $description';
    }
    return title;
  }

  String spokenTextFor(Map<String, dynamic> reminder) {
    final title = reminder['title']?.toString().trim() ?? '';
    final description = reminder['description']?.toString().trim() ?? '';
    return TtsLanguageService.reminderSpeech(title, description);
  }

  Map<String, dynamic> alarmParamsFor(Map<String, dynamic> reminder) {
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
      'repeatIntervalMinutes': repeatIntervalMinutes0(reminder),
      'priority': reminder['priority']?.toString(),
      'language': reminder['language']?.toString(),
      'retryCount': reminder['retryCount'] is int
          ? reminder['retryCount']
          : int.tryParse(reminder['retryCount']?.toString() ?? '') ?? 0,
      'markMissedOnFire': reminder['markMissedOnFire'] == true,
    };
  }

  int repeatIntervalMinutes0(Map<String, dynamic> reminder) {
    final directValue = reminder['repeatIntervalMinutes'];
    if (directValue is int && directValue > 0) return directValue;
    if (directValue is String) {
      final parsed = int.tryParse(directValue);
      if (parsed != null && parsed > 0) return parsed;
    }

    final repeatType = reminder['repeat_type']?.toString().toLowerCase();
    final customRepeat = customRepeatMinutes(repeatType);
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
          (isCompleted(latestReminder) ||
              isCanceled(latestReminder) ||
              isSkipped(latestReminder) ||
              isMissed(latestReminder))) {
        debugPrint(
          'Reminder alarm $alarmId ignored because reminder $id is already '
          'completed, skipped, cancelled, or missed.',
        );
        await cancelAlarmById(alarmId);
        return;
      }
    }

    final scheduledAt = dateTimeFromValue(
      reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
    );
    if (scheduledAt == null) return;
    await markOccurrenceFired(reminder, scheduledAt);

    if (reminder['markMissedOnFire'] == true) {
      await markOccurrenceFired(reminder, scheduledAt);
      await markReminderMissedIfStillPending(alarmId, reminder);
      return;
    }

    if (reminder[_localNotificationScheduledKey] != true) {
      try {
        await showReminderNotification(alarmId, reminder, scheduledAt);
      } catch (error, stackTrace) {
        debugPrint('Reminder notification failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    notifyDueReminder(alarmId, reminder, scheduledAt);

    final text = spokenTextFor(reminder);
    final reminderId = id ?? 'unknown';
    bool inworldSuccess = false;

    try {
      final inworldService = InworldTtsService();
      final filePath = await inworldService.generateSpeechFile(
        text,
        reminderId,
        languageCode:
            reminder['language']?.toString() ??
            TtsLanguageService.currentLanguage.code,
      );
      if (filePath != null && filePath.isNotEmpty) {
        inworldSuccess = await inworldService.playAudio(filePath);
      }
    } catch (error) {
      debugPrint('Inworld TTS generation or playback failed: $error');
    }

    if (!inworldSuccess) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await speakNativeReminderNow(alarmId: alarmId, reminder: reminder);
      }
    }

    await markOccurrenceFired(reminder, scheduledAt);
    await scheduleIgnoredRetryOrMiss(alarmId: alarmId, reminder: reminder);

    if (defaultTargetPlatform == TargetPlatform.android) return;

    if (!inworldSuccess) {
      try {
        await speakReminder(reminder);
      } catch (error, stackTrace) {
        debugPrint('Reminder speech failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    await initialize(requestPermissions: false);

    if (response.actionId != _skipActionId &&
        response.actionId != _doneActionId) {
      await queueDueReminderFromNotificationTap(response);
      return;
    }

    final payload = payloadFrom(response.payload);
    if (payload == null) {
      debugPrint(
        'Reminder notification action ignored: missing payload for '
        '${response.actionId}.',
      );
      return;
    }

    await applyNotificationAction(
      actionId: response.actionId,
      payload: payload,
    );
  }

  DateTime? dateTimeFromValue(Object? value) {
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

  Future<void> showReminderNotification(
    int alarmId,
    Map<String, dynamic> reminder,
    DateTime scheduledAt,
  ) async {
    if (kDebugMode) {
      debugPrint(
        'Showing reminder notification $alarmId for '
        '${reminder['title']} at ${DateTime.now().toIso8601String()}.',
      );
    }
    await _plugin.show(
      id: alarmId,
      title: TtsLanguageService.notificationTitle(),
      body: bodyFor(reminder, scheduledAt),
      notificationDetails: details(),
      payload: payloadFor(alarmId, reminder),
    );
  }

  Future<void> speakReminder(Map<String, dynamic> reminder) {
    final text = spokenTextFor(reminder);
    return enqueueSpeech(() async {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await TtsLanguageService.applyCurrentLanguage(_tts);
      await _tts.stop();
      await _tts.speak(text);
    });
  }

  Future<void> speakNativeReminderNow({
    required int alarmId,
    required Map<String, dynamic> reminder,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final text = spokenTextFor(reminder);
    if (text.trim().isEmpty) return;

    try {
      await _nativeReminderChannel.invokeMethod<void>('speakReminderNow', {
        'alarmId': alarmId,
        'text': text,
        'languageCode': TtsLanguageService.currentLanguage.code,
      });
    } catch (error) {
      debugPrint('Native reminder speech trigger failed: $error');
    }
  }

  Future<void> applyNotificationAction({
    required String? actionId,
    required _NotificationPayload payload,
  }) async {
    try {
      debugPrint(
        'Reminder notification action received: $actionId '
        'alarm=${payload.alarmId} reminder=${payload.reminderId}.',
      );

      await cancelActionAlarms(payload);
      await _tts.stop();
      try {
        await InworldTtsService().stopAudio();
      } catch (e) {
        debugPrint('Error stopping Inworld audio: $e');
      }

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
        await rescheduleRepeatingReminder(payload.reminderId);
        debugPrint('Reminder ${payload.reminderId} marked completed.');
        return;
      }

      if (actionId == _skipActionId) {
        await repository.markReminderSkippedById(payload.reminderId);
        await rescheduleRepeatingReminder(payload.reminderId);
        debugPrint('Reminder ${payload.reminderId} skipped for now.');
        return;
      }
    } catch (error, stackTrace) {
      debugPrint('Reminder notification action failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> scheduleIgnoredRetryOrMiss({
    required int alarmId,
    required Map<String, dynamic> reminder,
  }) async {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return;

    final retryCount = reminder['retryCount'] is int
        ? reminder['retryCount'] as int
        : int.tryParse(reminder['retryCount']?.toString() ?? '') ?? 0;
    final nextReminder = Map<String, dynamic>.from(reminder);
    if (retryCount < _maxIgnoredAttempts - 1) {
      nextReminder
        ..['retryCount'] = retryCount + 1
        ..['markMissedOnFire'] = false;
    } else {
      nextReminder
        ..['retryCount'] = retryCount
        ..['markMissedOnFire'] = true;
    }

    final retryTime = DateTime.now().add(_ignoredRetryDelay);
    final scheduled = await scheduleAlarm(
      notificationTime: retryTime,
      alarmId: alarmId,
      params: nextReminder,
    );
    if (!scheduled) {
      debugPrint('Ignored reminder retry scheduling failed for $id.');
      return;
    }
    await scheduleNativeSpeechAlarm(
      notificationTime: retryTime,
      alarmId: alarmId,
      reminder: nextReminder,
    );
    await addScheduledId(alarmId);
  }

  Future<void> markReminderMissedIfStillPending(
    int alarmId,
    Map<String, dynamic> reminder,
  ) async {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return;

    final repository = ReminderRepository();
    final latestReminder = await repository.loadReminderById(id);
    if (latestReminder != null &&
        (isCompleted(latestReminder) ||
            isCanceled(latestReminder) ||
            isSkipped(latestReminder) ||
            isMissed(latestReminder))) {
      await cancelAlarmById(alarmId);
      return;
    }

    await repository.markReminderMissedById(id);
    await _plugin.cancel(id: alarmId);
    await removeScheduledId(alarmId);
    await removeRepeatConfig(alarmId);
    await rescheduleRepeatingReminder(id);
    debugPrint('Reminder $id marked missed after ignored retries.');
  }

  void notifyDueReminder(
    int alarmId,
    Map<String, dynamic> reminder,
    DateTime scheduledAt,
  ) {
    final event = ReminderDueEvent(
      alarmId: alarmId,
      reminder: Map<String, dynamic>.from(reminder),
      scheduledAt: scheduledAt,
    );
    unawaited(persistPendingDueReminder(event));
    if (_dueReminderController.isClosed) return;
    _dueReminderController.add(event);
  }

  Future<void> persistPendingDueReminder(ReminderDueEvent event) async {
    final reminderId = event.reminder['id']?.toString();
    if (reminderId == null || reminderId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final storageKey =
        '$_pendingDuePrefix$reminderId.${event.scheduledAt.millisecondsSinceEpoch}';
    await prefs.setString(
      storageKey,
      jsonEncode({
        'alarmId': event.alarmId,
        'reminder': event.reminder,
        'scheduledAtMillis': event.scheduledAt.millisecondsSinceEpoch,
      }),
    );
  }

  Future<List<ReminderDueEvent>> drainPendingDueReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final storageKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(_pendingDuePrefix))
        .toList();
    final events = <ReminderDueEvent>[];

    for (final storageKey in storageKeys) {
      final raw = prefs.getString(storageKey);
      await prefs.remove(storageKey);
      if (raw == null || raw.isEmpty) continue;

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;

        final alarmId = decoded['alarmId'];
        final parsedAlarmId = alarmId is int
            ? alarmId
            : int.tryParse(alarmId?.toString() ?? '');
        final scheduledAtMillis = decoded['scheduledAtMillis'];
        final parsedScheduledAt = scheduledAtMillis is int
            ? scheduledAtMillis
            : int.tryParse(scheduledAtMillis?.toString() ?? '');
        final reminder = decoded['reminder'];
        if (parsedAlarmId == null ||
            parsedScheduledAt == null ||
            reminder is! Map) {
          continue;
        }

        events.add(
          ReminderDueEvent(
            alarmId: parsedAlarmId,
            reminder: Map<String, dynamic>.from(reminder),
            scheduledAt: DateTime.fromMillisecondsSinceEpoch(
              parsedScheduledAt,
            ),
          ),
        );
      } catch (error) {
        debugPrint('Pending due reminder parse failed: $error');
      }
    }

    return events;
  }

  Future<void> queueDueReminderFromNotificationTap(
    NotificationResponse response,
  ) async {
    final payload = payloadFrom(response.payload);
    if (payload == null || payload.reminderId.isEmpty) return;

    final reminder = await ReminderRepository().loadReminderById(
      payload.reminderId,
    );
    if (reminder == null) return;

    final scheduledAt = dateTimeFromValue(
      reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
    );
    if (scheduledAt == null) return;

    await persistPendingDueReminder(
      ReminderDueEvent(
        alarmId: payload.alarmId,
        reminder: reminder,
        scheduledAt: scheduledAt,
      ),
    );
  }

  Future<NotificationAppLaunchDetails?>
  getNotificationLaunchDetails() async {
    await initialize(requestPermissions: false);
    return _plugin.getNotificationAppLaunchDetails();
  }

  Future<void> enqueueSpeech(Future<void> Function() action) {
    _speechQueue = _speechQueue.then((_) => action()).catchError((
      error,
      stackTrace,
    ) {
      debugPrint('Reminder speech queue failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    });
    return _speechQueue;
  }

  Future<bool> reconcileDueReminders(
    List<Map<String, dynamic>> reminders,
  ) async {
    if (!SettingsController.instance.notificationsEnabled) return false;

    final now = DateTime.now();
    final repository = ReminderRepository();
    var changed = false;
    for (final reminder in reminders) {
      if (isCompleted(reminder) ||
          isCanceled(reminder) ||
          isSkipped(reminder) ||
          isMissed(reminder)) {
        continue;
      }

      final scheduledAt = dateTimeFromValue(
        reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
      );
      if (scheduledAt == null || scheduledAt.isAfter(now)) continue;

      final isFired = await hasOccurrenceFired(reminder, scheduledAt);
      if (isFired && now.difference(scheduledAt) <= _lateReminderGrace) {
        continue;
      }

      if (!isFired && now.difference(scheduledAt) <= _lateReminderGrace) {
        await handleAlarmFired(notificationIdFor(reminder['id'].toString()), {
          ...alarmParamsFor(reminder),
          'reconciledLateFire': true,
        });
        changed = true;
        continue;
      }

      await markOccurrenceFired(reminder, scheduledAt);
      await repository.markReminderMissed(reminder);
      changed = true;
      if (isRepeating0(reminder)) {
        final id = reminder['id']?.toString();
        if (id != null) {
          final updated = await repository.loadReminderById(id);
          if (updated != null) {
            await scheduleReminder(updated);
          }
        }
      }
    }
    return changed;
  }

  Future<bool> hasOccurrenceFired(
    Map<String, dynamic> reminder,
    DateTime scheduledAt,
  ) async {
    final key = firedOccurrenceKey(reminder, scheduledAt);
    if (key == null) return false;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<void> markOccurrenceFired(
    Map<String, dynamic> reminder,
    DateTime scheduledAt,
  ) async {
    final key = firedOccurrenceKey(reminder, scheduledAt);
    if (key == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  String? firedOccurrenceKey(Map<String, dynamic> reminder, DateTime at) {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return '$_firedOccurrencePrefix$id.${at.millisecondsSinceEpoch}';
  }

  Future<void> saveRepeatConfig(
    int alarmId,
    Map<String, dynamic> reminder,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(repeatConfigKey(alarmId), jsonEncode(reminder));
  }

  Future<void> removeRepeatConfig(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(repeatConfigKey(alarmId));
  }

  Future<void> clearRepeatConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_repeatConfigPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> addScheduledId(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    final alarmIdString = alarmId.toString();
    if (!ids.contains(alarmIdString)) {
      ids.add(alarmIdString);
      await prefs.setStringList(_scheduledIdsKey, ids);
    }
  }

  Future<void> removeScheduledId(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    final alarmIdString = alarmId.toString();
    if (ids.remove(alarmIdString)) {
      await prefs.setStringList(_scheduledIdsKey, ids);
    }
  }

  Future<void> cancelAlarmById(
    int alarmId, {
    bool removeTracking = true,
  }) async {
    await AndroidAlarmManager.cancel(alarmId);
    await cancelNativeSpeechAlarm(alarmId);
    await _plugin.cancel(id: alarmId);
    if (removeTracking) {
      await removeScheduledId(alarmId);
      await removeRepeatConfig(alarmId);
    }
  }

  Future<void> cancelActionAlarms(_NotificationPayload payload) async {
    final alarmIds = <int>{payload.alarmId};
    if (payload.reminderId.isNotEmpty) {
      alarmIds.add(notificationIdFor(payload.reminderId));
    }

    for (final alarmId in alarmIds) {
      await cancelAlarmById(alarmId);
    }
  }

  Future<bool> scheduleAlarm({
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

  Future<void> cancelTrackedAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    for (final id in ids) {
      final alarmId = int.tryParse(id);
      if (alarmId == null) continue;
      await AndroidAlarmManager.cancel(alarmId);
      await cancelNativeSpeechAlarm(alarmId);
      await _plugin.cancel(id: alarmId);
    }
    await prefs.remove(_scheduledIdsKey);
    await clearRepeatConfigs();
  }

  String repeatConfigKey(int alarmId) => '$_repeatConfigPrefix$alarmId';

  Duration repeatIntervalDuration(int repeatIntervalMinutes) {
    if (repeatIntervalMinutes == 0) return const Duration(seconds: 30);
    return Duration(minutes: repeatIntervalMinutes);
  }

  int? customRepeatMinutes(String? repeatType) {
    if (repeatType == null) return null;
    final match = RegExp(r'^custom:(\d+)$').firstMatch(repeatType);
    if (match == null) return null;
    final minutes = int.tryParse(match.group(1)!);
    if (minutes == null || minutes < 0) return null;
    return minutes;
  }

  bool isCompleted(Map<String, dynamic> reminder) {
    return reminder['isCompleted'] == true || reminder['is_completed'] == true;
  }

  bool isCanceled(Map<String, dynamic> reminder) {
    return reminder['isCanceled'] == true ||
        reminder['is_canceled'] == true ||
        reminder['sync_status'] == 'canceled' ||
        reminder['sync_status'] == 'cancelled' ||
        reminder['task_status'] == 'cancelled';
  }

  bool isSkipped(Map<String, dynamic> reminder) {
    return reminder['task_status'] == 'skipped' && !isRepeating0(reminder);
  }

  bool isMissed(Map<String, dynamic> reminder) {
    return reminder['task_status'] == 'missed' && !isRepeating0(reminder);
  }

  Future<void> rescheduleRepeatingReminder(String reminderId) async {
    final reminder = await ReminderRepository().loadReminderById(reminderId);
    if (reminder == null || !isRepeating0(reminder)) return;
    if (isCompleted(reminder) || isCanceled(reminder)) return;

    debugPrint(
      'Rescheduling next occurrence for repeating reminder $reminderId.',
    );
    await scheduleReminder(reminder);
  }

  bool isRepeating0(Map<String, dynamic> reminder) {
    final repeatType = reminder['repeat_type']?.toString().toLowerCase();
    return reminder['isRepeating'] == true ||
        reminder['is_repeating'] == true ||
        (repeatType != null && repeatType.isNotEmpty && repeatType != 'none');
  }

  List<DarwinNotificationCategory> darwinReminderCategories() {
    return [
      darwinReminderCategory(
        identifier: _darwinEnglishCategoryId,
        doneLabel: 'Done',
        skipLabel: 'Skip',
      ),
      darwinReminderCategory(
        identifier: _darwinTagalogCategoryId,
        doneLabel: 'Tapos',
        skipLabel: 'Laktawan',
      ),
    ];
  }

  DarwinNotificationCategory darwinReminderCategory({
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

  String currentDarwinCategoryId() {
    return TtsLanguageService.currentLanguage == AppSpeechLanguage.tagalog
        ? _darwinTagalogCategoryId
        : _darwinEnglishCategoryId;
  }

  Future<bool> scheduleLocalNotification({
    required DateTime notificationTime,
    required int alarmId,
    required Map<String, dynamic> reminder,
    required bool canScheduleExactAlarms,
  }) async {
    try {
      final scheduledAt = dateTimeFromValue(
        reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
      );
      try {
        await _plugin.zonedSchedule(
          id: alarmId,
          title: TtsLanguageService.notificationTitle(),
          body: bodyFor(reminder, scheduledAt ?? notificationTime),
          scheduledDate: tz.TZDateTime.from(notificationTime, tz.local),
          notificationDetails: details(),
          androidScheduleMode: canScheduleExactAlarms
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payloadFor(alarmId, reminder),
        );
      } on PlatformException catch (error) {
        if (!canScheduleExactAlarms) rethrow;
        debugPrint(
          'Exact local notification scheduling failed; using inexact fallback: '
          '$error',
        );
        await _plugin.zonedSchedule(
          id: alarmId,
          title: TtsLanguageService.notificationTitle(),
          body: bodyFor(reminder, scheduledAt ?? notificationTime),
          scheduledDate: tz.TZDateTime.from(notificationTime, tz.local),
          notificationDetails: details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payloadFor(alarmId, reminder),
        );
      }
      return true;
    } catch (error, stackTrace) {
      debugPrint('Reminder fallback scheduling threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> initializeTimeZone() async {
    tz.initializeTimeZones();
    final timeZoneName = await deviceTimeZoneName();
    final locationName = normalizeTimeZoneName(timeZoneName);

    try {
      tz.setLocalLocation(tz.getLocation(locationName));
    } catch (error) {
      debugPrint('Device timezone "$locationName" is unavailable: $error');
      tz.setLocalLocation(tz.UTC);
    }

    final prefs = await SharedPreferences.getInstance();
    final previousTimeZone = prefs.getString(_lastTimeZoneKey);
    final activeTimeZone = tz.local.name;
    if (previousTimeZone != activeTimeZone) {
      await prefs.setString(_lastTimeZoneKey, activeTimeZone);
      if (previousTimeZone != null) {
        debugPrint(
          'Reminder timezone changed from $previousTimeZone to $activeTimeZone.',
        );
      }
    }
  }

  Future<String> deviceTimeZoneName() async {
    try {
      final timeZoneName = await _nativeReminderChannel.invokeMethod<String>(
        'getTimeZoneName',
      );
      if (timeZoneName != null && timeZoneName.trim().isNotEmpty) {
        return timeZoneName.trim();
      }
    } catch (error) {
      debugPrint('Device timezone lookup failed: $error');
    }

    return DateTime.now().timeZoneName;
  }

  String normalizeTimeZoneName(String timeZoneName) {
    final normalized = timeZoneName.trim();
    switch (normalized.toUpperCase()) {
      case 'GMT':
      case 'UTC':
      case 'UT':
      case 'Z':
        return 'UTC';
      default:
        return normalized;
    }
  }

  Future<void> scheduleNativeSpeechAlarm({
    required DateTime notificationTime,
    required int alarmId,
    required Map<String, dynamic> reminder,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!notificationTime.isAfter(DateTime.now())) return;

    try {
      await _nativeReminderChannel.invokeMethod<void>('scheduleSpeechAlarm', {
        'alarmId': alarmId,
        'triggerAtMillis': notificationTime.millisecondsSinceEpoch,
        'reminderId': reminder['id']?.toString() ?? '',
        'title': TtsLanguageService.notificationTitle(),
        'body': bodyFor(reminder, notificationTime),
        'text': spokenTextFor(reminder),
        'languageCode': TtsLanguageService.currentLanguage.code,
      });
    } catch (error) {
      debugPrint('Native reminder speech alarm scheduling failed: $error');
    }
  }

  Future<void> cancelNativeSpeechAlarm(int alarmId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _nativeReminderChannel.invokeMethod<void>('cancelSpeechAlarm', {
        'alarmId': alarmId,
      });
    } catch (error) {
      debugPrint('Native reminder speech alarm cancel failed: $error');
    }
  }

  Future<void> ensureAlarmManagerInitialized() async {
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

  Future<bool> canScheduleExactAlarms0() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<void> ensureSettingsLoaded() async {
    try {
      SettingsController.instance;
    } catch (_) {
      await SettingsController.load();
    }
  }

  String payloadFor(int alarmId, Map<String, dynamic> reminder) {
    return jsonEncode({
      'alarmId': alarmId,
      'reminderId': reminder['id']?.toString() ?? '',
    });
  }

  _NotificationPayload? payloadFrom(String? rawPayload) {
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

  int notificationIdFor(String id) {
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

class ReminderDueEvent {
  const ReminderDueEvent({
    required this.alarmId,
    required this.reminder,
    required this.scheduledAt,
  });

  final int alarmId;
  final Map<String, dynamic> reminder;
  final DateTime scheduledAt;
}
