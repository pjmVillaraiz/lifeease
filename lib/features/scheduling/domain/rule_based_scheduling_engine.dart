enum ConstraintSeverity { soft, hard }

enum ReminderPriority { low, normal, high, emergency }

class SchedulingSuggestion {
  final int suggestedLeadMinutes;
  final String note;
  final ReminderPriority priority;

  const SchedulingSuggestion({
    required this.suggestedLeadMinutes,
    required this.note,
    this.priority = ReminderPriority.normal,
  });
}

class ReminderRule {
  final String id;
  final String description;
  final ConstraintSeverity severity;
  final bool Function(
    SchedulingRequest request,
    List<ScheduledReminder> existing,
  )
  isViolated;

  const ReminderRule({
    required this.id,
    required this.description,
    required this.severity,
    required this.isViolated,
  });
}

class SchedulingRequest {
  final String title;
  final String category;
  final DateTime scheduledAt;
  final bool isRepeating;
  final int repeatIntervalMinutes;
  final ReminderPriority priority;

  const SchedulingRequest({
    required this.title,
    required this.category,
    required this.scheduledAt,
    this.isRepeating = false,
    this.repeatIntervalMinutes = 0,
    this.priority = ReminderPriority.normal,
  });
}

class ScheduledReminder {
  final String title;
  final String category;
  final DateTime scheduledAt;
  final ReminderPriority priority;

  const ScheduledReminder({
    required this.title,
    required this.category,
    required this.scheduledAt,
    this.priority = ReminderPriority.normal,
  });
}

class SchedulingDecision {
  final bool allowed;
  final DateTime scheduledAt;
  final List<String> hardViolations;
  final List<String> softWarnings;
  final ReminderPriority priority;

  const SchedulingDecision({
    required this.allowed,
    required this.scheduledAt,
    required this.hardViolations,
    required this.softWarnings,
    required this.priority,
  });
}

class RuleBasedSchedulingEngine {
  late final List<ReminderRule> _rules = [
    ReminderRule(
      id: 'medicine_overlap',
      description: 'Medicine reminders cannot overlap within 15 minutes.',
      severity: ConstraintSeverity.hard,
      isViolated: (request, existing) {
        if (request.category != 'pill') return false;
        return existing.where((item) => item.category == 'pill').any((item) {
          return item.scheduledAt.difference(request.scheduledAt).abs() <
              const Duration(minutes: 15);
        });
      },
    ),
    ReminderRule(
      id: 'sleep_quiet_hours',
      description: 'Sleep or low priority reminders are muted after bedtime.',
      severity: ConstraintSeverity.soft,
      isViolated: (request, _) {
        final hour = request.scheduledAt.hour;
        return request.priority != ReminderPriority.emergency &&
            (hour >= 22 || hour < 6);
      },
    ),
    ReminderRule(
      id: 'child_study_window',
      description: 'Child study reminders should be between 4 PM and 7 PM.',
      severity: ConstraintSeverity.soft,
      isViolated: (request, _) {
        final title = request.title.toLowerCase();
        if (!title.contains('study') && !title.contains('homework')) {
          return false;
        }
        final hour = request.scheduledAt.hour;
        return hour < 16 || hour > 19;
      },
    ),
  ];

  SchedulingSuggestion buildSuggestion({
    required String category,
    required bool isRepeating,
  }) {
    final normalized = category.toLowerCase();

    if (normalized == 'emergency') {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 0,
        note: 'Emergency reminders override other notifications.',
        priority: ReminderPriority.emergency,
      );
    }
    if (normalized == 'pill') {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 15,
        note: 'Medication reminders work best with 15-minute lead time.',
        priority: ReminderPriority.high,
      );
    }
    if (normalized == 'appointment') {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 30,
        note: 'Appointments benefit from earlier warning for preparation.',
        priority: ReminderPriority.high,
      );
    }
    if (normalized == 'food') {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 10,
        note: 'Meal reminders can stay short and simple.',
      );
    }
    if (isRepeating) {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 10,
        note: 'Repeating reminders usually need moderate lead time.',
      );
    }
    return const SchedulingSuggestion(
      suggestedLeadMinutes: 5,
      note: 'Default quick reminder lead time.',
    );
  }

  SchedulingDecision evaluate(
    SchedulingRequest request,
    List<ScheduledReminder> existing,
  ) {
    if (request.priority == ReminderPriority.emergency) {
      return SchedulingDecision(
        allowed: true,
        scheduledAt: request.scheduledAt,
        hardViolations: const [],
        softWarnings: const ['Emergency reminder overrides all constraints.'],
        priority: ReminderPriority.emergency,
      );
    }

    final hardViolations = <String>[];
    final softWarnings = <String>[];
    for (final rule in _rules) {
      if (!rule.isViolated(request, existing)) continue;
      if (rule.severity == ConstraintSeverity.hard) {
        hardViolations.add(rule.description);
      } else {
        softWarnings.add(rule.description);
      }
    }

    final adjustedTime = hardViolations.isEmpty
        ? request.scheduledAt
        : autoReschedule(request.scheduledAt, existing);

    return SchedulingDecision(
      allowed: hardViolations.isEmpty,
      scheduledAt: adjustedTime,
      hardViolations: hardViolations,
      softWarnings: softWarnings,
      priority: request.priority,
    );
  }

  DateTime autoReschedule(
    DateTime preferred,
    List<ScheduledReminder> existing, {
    Duration step = const Duration(minutes: 15),
  }) {
    var candidate = preferred;
    for (var i = 0; i < 12; i++) {
      final hasConflict = existing.any(
        (item) => item.scheduledAt.difference(candidate).abs() < step,
      );
      if (!hasConflict) return candidate;
      candidate = candidate.add(step);
    }
    return candidate;
  }

  DateTime snooze(DateTime scheduledAt, {int minutes = 10}) {
    return scheduledAt.add(Duration(minutes: minutes));
  }
}
