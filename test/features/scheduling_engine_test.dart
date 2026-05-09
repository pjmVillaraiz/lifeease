import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/features/scheduling/domain/rule_based_scheduling_engine.dart';

void main() {
  group('RuleBasedSchedulingEngine', () {
    test('blocks overlapping medication reminders', () {
      final engine = RuleBasedSchedulingEngine();
      final scheduledAt = DateTime(2026, 5, 9, 8);

      final decision = engine.evaluate(
        SchedulingRequest(
          title: 'Take medicine',
          category: 'pill',
          scheduledAt: scheduledAt.add(const Duration(minutes: 5)),
        ),
        [
          ScheduledReminder(
            title: 'Metformin',
            category: 'pill',
            scheduledAt: scheduledAt,
          ),
        ],
      );

      expect(decision.allowed, isFalse);
      expect(decision.hardViolations, isNotEmpty);
    });

    test('allows emergency reminders during quiet hours', () {
      final engine = RuleBasedSchedulingEngine();
      final decision = engine.evaluate(
        SchedulingRequest(
          title: 'Call emergency contact',
          category: 'emergency',
          scheduledAt: DateTime(2026, 5, 9, 23),
          priority: ReminderPriority.emergency,
        ),
        const [],
      );

      expect(decision.allowed, isTrue);
      expect(decision.priority, ReminderPriority.emergency);
    });
  });
}
