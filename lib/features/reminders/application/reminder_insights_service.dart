import 'package:intl/intl.dart';

import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/features/reminders/presentation/home_screen/home_screen.dart';

enum ReminderStatsPeriod { day, week, month }

class ReminderStats {
  const ReminderStats({
    required this.total,
    required this.completed,
    required this.skipped,
    required this.missed,
    required this.pending,
    required this.medicationTotal,
    required this.medicationCompleted,
  });

  final int total;
  final int completed;
  final int skipped;
  final int missed;
  final int pending;
  final int medicationTotal;
  final int medicationCompleted;

  int get completionRate =>
      total == 0 ? 0 : ((completed / total) * 100).round().clamp(0, 100);

  int get medicationAdherence => medicationTotal == 0
      ? 0
      : ((medicationCompleted / medicationTotal) * 100).round().clamp(0, 100);
}

class ReminderInsightsService {
  const ReminderInsightsService();

  ReminderStats statsFor(
    List<ReminderModel> reminders, {
    required ReminderStatsPeriod period,
  }) {
    final now = DateTime.now();
    final scoped = reminders.where((reminder) {
      final scheduled = DateTime.fromMillisecondsSinceEpoch(
        reminder.scheduledTimeMillis,
      );
      return _isInPeriod(scheduled, now, period);
    }).toList();

    final completed = scoped
        .where((r) => r.isCompleted || r.isCompletedToday)
        .length;
    final skipped = scoped.where((r) => r.isSkippedToday).length;
    final missed = scoped.where((r) => r.isMissedToday || _isOverdue(r)).length;
    final pending = scoped
        .where(
          (r) =>
              !r.isCompleted &&
              !r.isCanceled &&
              !r.isSkippedToday &&
              !r.isMissedToday &&
              !_isOverdue(r),
        )
        .length;
    final medication = scoped.where(_isMedication).toList();

    return ReminderStats(
      total: scoped.length,
      completed: completed,
      skipped: skipped,
      missed: missed,
      pending: pending,
      medicationTotal: medication.length,
      medicationCompleted: medication
          .where((r) => r.isCompleted || r.isCompletedToday)
          .length,
    );
  }

  List<ReminderModel> todaySchedule(List<ReminderModel> reminders) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final today = reminders.where((reminder) {
      final scheduled = DateTime.fromMillisecondsSinceEpoch(
        reminder.scheduledTimeMillis,
      );
      return !scheduled.isBefore(start) && scheduled.isBefore(end);
    }).toList();

    today.sort(
      (a, b) => a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis),
    );
    return today;
  }

  String spokenSchedule(List<ReminderModel> reminders) {
    final schedule = todaySchedule(reminders);
    final isTagalog =
        TtsLanguageService.currentLanguage == AppSpeechLanguage.tagalog;
    final greeting = _spokenGreeting(isTagalog);

    if (schedule.isEmpty) {
      return isTagalog
          ? '$greeting. Wala kang nakatakdang paalala ngayong araw.'
          : '$greeting. You have no reminders scheduled today.';
    }

    final countText = isTagalog
        ? 'Mayroon kang ${schedule.length} na paalala ngayong araw.'
        : 'You have ${schedule.length} reminders scheduled today.';
    final entries = schedule
        .map((reminder) {
          final time = DateFormat('h:mm a').format(
            DateTime.fromMillisecondsSinceEpoch(reminder.scheduledTimeMillis),
          );
          final title = reminder.title.trim();
          final status = _statusText(reminder, isTagalog);
          if (isTagalog) {
            return 'Sa $time, $title. $status.';
          }
          return 'At $time, $title. $status.';
        })
        .join(' ');

    return '$greeting. $countText $entries';
  }

  bool _isInPeriod(
    DateTime scheduled,
    DateTime now,
    ReminderStatsPeriod period,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    late final DateTime start;
    late final DateTime end;

    switch (period) {
      case ReminderStatsPeriod.day:
        start = today;
        end = today.add(const Duration(days: 1));
      case ReminderStatsPeriod.week:
        start = today.subtract(Duration(days: today.weekday - 1));
        end = start.add(const Duration(days: 7));
      case ReminderStatsPeriod.month:
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1);
    }

    return !scheduled.isBefore(start) && scheduled.isBefore(end);
  }

  bool _isOverdue(ReminderModel reminder) {
    return !reminder.isCompleted &&
        !reminder.isCanceled &&
        !reminder.isSkipped &&
        !reminder.isMissed &&
        reminder.scheduledTimeMillis < DateTime.now().millisecondsSinceEpoch;
  }

  bool _isMedication(ReminderModel reminder) {
    final category = reminder.category.toLowerCase();
    final text = '${reminder.title} ${reminder.description}'.toLowerCase();
    return category == 'pill' ||
        text.contains('medicine') ||
        text.contains('medication') ||
        text.contains('gamot') ||
        text.contains('vitamin');
  }

  String _spokenGreeting(bool isTagalog) {
    final hour = DateTime.now().hour;
    if (isTagalog) {
      if (hour < 12) return 'Magandang umaga';
      if (hour < 18) return 'Magandang hapon';
      return 'Magandang gabi';
    }
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _statusText(ReminderModel reminder, bool isTagalog) {
    if (reminder.isCompleted || reminder.isCompletedToday) {
      return isTagalog ? 'Tapos na ito' : 'This is completed';
    }
    if (reminder.isSkippedToday) {
      return isTagalog ? 'Nilaktawan ito' : 'This was skipped';
    }
    if (reminder.isMissedToday || _isOverdue(reminder)) {
      return isTagalog ? 'Nalagpasan ito' : 'This is missed';
    }
    return isTagalog ? 'Nakabinbin ito' : 'This is pending';
  }
}
