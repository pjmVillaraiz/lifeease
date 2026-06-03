import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/services/voice/command_processor.dart';
import 'package:lifeease/services/voice/reminder_parser.dart';

void main() {
  test('voice command creates a reminder for take pill at 10pm', () {
    final processor = CommandProcessor(
      reminderParser: ReminderParser(now: () => DateTime(2026, 6, 2, 9)),
    );

    final result = processor.process('take pill at 10pm');

    expect(result.intent, VoiceCommandIntent.createReminder);
    expect(result.reminderDraft, isNotNull);
    expect(result.reminderDraft!.title, 'Take pill');
    expect(result.reminderDraft!.scheduledAt.year, 2026);
    expect(result.reminderDraft!.scheduledAt.month, 6);
    expect(result.reminderDraft!.scheduledAt.day, 2);
    expect(result.reminderDraft!.scheduledAt.hour, 22);
    expect(result.reminderDraft!.scheduledAt.minute, 0);
    expect(result.reminderDraft!.repeatType, 'none');
    expect(result.reminderHasExplicitTime, isTrue);
  });

  test('explicit reminder without time is flagged for follow-up', () {
    final processor = CommandProcessor(
      reminderParser: ReminderParser(now: () => DateTime(2026, 6, 2, 9)),
    );

    final result = processor.process('remind me to take pill');

    expect(result.intent, VoiceCommandIntent.createReminder);
    expect(result.reminderDraft, isNotNull);
    expect(result.reminderHasExplicitTime, isFalse);
  });

  test('implicit take pill command creates a reminder draft', () {
    final processor = CommandProcessor(
      reminderParser: ReminderParser(now: () => DateTime(2026, 6, 2, 9)),
    );

    final result = processor.process('take pill');

    expect(result.intent, VoiceCommandIntent.createReminder);
    expect(result.reminderDraft, isNotNull);
    expect(result.reminderDraft!.title, 'Take pill');
    expect(result.reminderHasExplicitTime, isFalse);
  });

  test('implicit make appointment command creates a reminder draft', () {
    final processor = CommandProcessor(
      reminderParser: ReminderParser(now: () => DateTime(2026, 6, 2, 9)),
    );

    final result = processor.process('make appointment');

    expect(result.intent, VoiceCommandIntent.createReminder);
    expect(result.reminderDraft, isNotNull);
    expect(result.reminderDraft!.title, 'Make appointment');
    expect(result.reminderHasExplicitTime, isFalse);
  });

  test('parser accepts implicit medication reminders with a time', () {
    final parser = ReminderParser(now: () => DateTime(2026, 6, 2, 9));

    final draft = parser.parse('take pill at 10pm');

    expect(draft, isNotNull);
    expect(draft!.title, 'Take pill');
    expect(draft.scheduledAt.hour, 22);
    expect(draft.hasExplicitTime, isTrue);
  });
}
