import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/notifications/reminder_notification_service.dart';

class DeviceLocation {
  const DeviceLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class LocationReminderService {
  LocationReminderService._();

  static final LocationReminderService instance = LocationReminderService._();

  static const MethodChannel _channel = MethodChannel(
    'lifeease/reminder_native',
  );
  static const double _defaultRadiusMeters = 180;
  static const String _statePrefix = 'lifeease.location_reminder.state.';
  static const String _triggerPrefix = 'lifeease.location_reminder.triggered.';

  Timer? _timer;
  bool _checking = false;

  Future<DeviceLocation?> currentLocation() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getCurrentLocation',
      );
      final latitude = (result?['latitude'] as num?)?.toDouble();
      final longitude = (result?['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) return null;
      return DeviceLocation(latitude: latitude, longitude: longitude);
    } on PlatformException catch (error) {
      debugPrint('Location lookup failed: $error');
      return null;
    }
  }

  void start() {
    _timer ??= Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(checkNow()),
    );
    unawaited(checkNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final location = await currentLocation();
      if (location == null) return;

      final reminders = await ReminderRepository().loadReminders();
      final prefs = await SharedPreferences.getInstance();
      for (final reminder in reminders) {
        if (!_isActiveLocationReminder(reminder)) continue;
        await _evaluateReminder(reminder, location, prefs);
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _evaluateReminder(
    Map<String, dynamic> reminder,
    DeviceLocation location,
    SharedPreferences prefs,
  ) async {
    final id = reminder['id']?.toString();
    final latitude = _doubleFrom(reminder['location_latitude']);
    final longitude = _doubleFrom(reminder['location_longitude']);
    if (id == null || latitude == null || longitude == null) return;

    final radius =
        _doubleFrom(reminder['location_radius_meters']) ?? _defaultRadiusMeters;
    final distance = _distanceMeters(
      location.latitude,
      location.longitude,
      latitude,
      longitude,
    );
    final isInside = distance <= radius;
    final stateKey = '$_statePrefix$id';
    final triggerKey = '$_triggerPrefix$id';
    final wasInside = prefs.getBool(stateKey);
    await prefs.setBool(stateKey, isInside);

    if (prefs.getBool(triggerKey) == true) return;

    final trigger = reminder['location_trigger']?.toString() ?? 'arrive';
    final shouldTrigger = trigger == 'leave'
        ? wasInside == true && !isInside
        : wasInside == false && isInside;

    if (!shouldTrigger) return;

    await prefs.setBool(triggerKey, true);
    await ReminderNotificationService.instance.triggerReminderNow({
      ...reminder,
      'scheduledTimeMillis': DateTime.now().millisecondsSinceEpoch,
      'reminder_time': DateTime.now().toIso8601String(),
    });
  }

  bool _isActiveLocationReminder(Map<String, dynamic> reminder) {
    return reminder['location_enabled'] == true &&
        reminder['is_completed'] != true &&
        reminder['isCompleted'] != true &&
        reminder['is_canceled'] != true &&
        reminder['isCanceled'] != true &&
        reminder['task_status'] != 'skipped' &&
        reminder['task_status'] != 'missed';
  }

  double? _doubleFrom(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_radians(lat1)) *
            cos(_radians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * pi / 180;
}
