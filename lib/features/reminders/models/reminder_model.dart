import 'package:lifeease/core/services/tts/tts_language_service.dart';

class ReminderModel {
  final String id;
  final String title;
  final String description;
  final int scheduledTimeMillis;
  final bool isCompleted;
  final bool isCanceled;
  final bool isSkipped;
  final bool isMissed;
  final bool isRepeating;
  final int repeatIntervalMinutes;
  final String category;
  final String userUid;
  final int createdAt;
  final bool isSynced;
  final String lastOccurrenceStatus;
  final String lastOccurrenceDate;
  final bool locationEnabled;
  final String locationTrigger;
  final String locationName;
  final double? locationLatitude;
  final double? locationLongitude;

  const ReminderModel({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTimeMillis,
    required this.isCompleted,
    required this.isCanceled,
    required this.isSkipped,
    required this.isMissed,
    required this.isRepeating,
    required this.repeatIntervalMinutes,
    required this.category,
    required this.userUid,
    required this.createdAt,
    required this.isSynced,
    this.lastOccurrenceStatus = '',
    this.lastOccurrenceDate = '',
    this.locationEnabled = false,
    this.locationTrigger = 'arrive',
    this.locationName = '',
    this.locationLatitude,
    this.locationLongitude,
  });

  factory ReminderModel.fromMap(Map<String, dynamic> map) {
    final scheduledAt = map['scheduledTimeMillis'] ?? map['reminder_time'];
    final createdValue = map['createdAt'] ?? map['created_at'];
    final repeatType = map['repeat_type']?.toString() ?? '';
    final isRepeatingValue =
        map['isRepeating'] as bool? ??
        (repeatType.isNotEmpty && repeatType != 'none');
    final taskStatus = map['task_status']?.toString();
    final lastOccurrenceStatus = map['last_occurrence_status']?.toString();

    return ReminderModel(
      id: map['id']?.toString() ?? DateTime.now().toIso8601String(),
      title: map['title']?.toString() ?? TtsLanguageService.reminderLabel(),
      description: map['description']?.toString() ?? '',
      scheduledTimeMillis: _millisFromValue(scheduledAt),
      isCompleted:
          map['isCompleted'] as bool? ?? map['is_completed'] as bool? ?? false,
      isCanceled:
          map['isCanceled'] as bool? ??
          map['is_canceled'] as bool? ??
          (map['sync_status'] == 'canceled' ||
              map['sync_status'] == 'cancelled' ||
              map['task_status'] == 'cancelled'),
      isSkipped:
          !isRepeatingValue &&
          (map['isSkipped'] as bool? ??
              (taskStatus == 'skipped' || lastOccurrenceStatus == 'skipped')),
      isMissed:
          !isRepeatingValue &&
          (map['isMissed'] as bool? ??
              (taskStatus == 'missed' || lastOccurrenceStatus == 'missed')),
      isRepeating: isRepeatingValue,
      repeatIntervalMinutes:
          map['repeatIntervalMinutes'] as int? ??
          _repeatMinutesFromType(map['repeat_type']?.toString()),
      category: map['category'] as String? ?? 'general',
      userUid: map['userUid'] as String? ?? '',
      createdAt: _millisFromValue(createdValue),
      isSynced: map['isSynced'] as bool? ?? map['sync_status'] == 'synced',
      lastOccurrenceStatus: lastOccurrenceStatus ?? '',
      lastOccurrenceDate: map['last_occurrence_date']?.toString() ?? '',
      locationEnabled: map['location_enabled'] == true,
      locationTrigger: map['location_trigger']?.toString() == 'leave'
          ? 'leave'
          : 'arrive',
      locationName: map['location_name']?.toString() ?? '',
      locationLatitude: _doubleFromValue(map['location_latitude']),
      locationLongitude: _doubleFromValue(map['location_longitude']),
    );
  }

  bool get isCompletedToday {
    return lastOccurrenceStatus == 'completed' &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  bool get isCanceledToday {
    return (lastOccurrenceStatus == 'cancelled' ||
            lastOccurrenceStatus == 'canceled') &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  bool get isSkippedToday {
    if (isSkipped && !isRepeating) return true;
    return (isSkipped || lastOccurrenceStatus == 'skipped') &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  bool get isMissedToday {
    if (isMissed && !isRepeating) return true;
    return (isMissed || lastOccurrenceStatus == 'missed') &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'scheduledTimeMillis': scheduledTimeMillis,
    'reminder_time': DateTime.fromMillisecondsSinceEpoch(
      scheduledTimeMillis,
    ).toIso8601String(),
    'isCompleted': isCompleted,
    'isCanceled': isCanceled,
    'is_canceled': isCanceled,
    'isSkipped': isSkipped,
    'isMissed': isMissed,
    'task_status': isCanceled
        ? 'cancelled'
        : isSkipped
        ? 'skipped'
        : isMissed
        ? 'missed'
        : 'active',
    'isRepeating': isRepeating,
    'repeatIntervalMinutes': repeatIntervalMinutes,
    'repeat_type': isRepeating
        ? _repeatTypeFromMinutes(repeatIntervalMinutes)
        : 'none',
    'category': category,
    'userUid': userUid,
    'createdAt': createdAt,
    'isSynced': isSynced,
    'last_occurrence_status': lastOccurrenceStatus,
    'last_occurrence_date': lastOccurrenceDate,
    'location_enabled': locationEnabled,
    'location_trigger': locationTrigger,
    'location_name': locationName,
    'location_latitude': locationLatitude,
    'location_longitude': locationLongitude,
  };

  static int _millisFromValue(Object? value) {
    if (value is int) return value;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ??
          int.tryParse(value) ??
          DateTime.now().millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  static double? _doubleFromValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int _repeatMinutesFromType(String? repeatType) {
    final customMatch = RegExp(
      r'^custom:(\d+)$',
    ).firstMatch(repeatType?.toLowerCase() ?? '');
    if (customMatch != null) {
      return int.tryParse(customMatch.group(1)!) ?? 0;
    }

    switch (repeatType) {
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

  static String _repeatTypeFromMinutes(int minutes) {
    if (minutes == 43200) return 'monthly';
    if (minutes == 21600) return 'twice_monthly';
    if (minutes == 10080) return 'weekly';
    if (minutes == 1440) return 'daily';
    return 'custom:$minutes';
  }

  static String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
