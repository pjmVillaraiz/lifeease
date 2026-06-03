import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/services/voice/command_processor.dart';
import 'package:lifeease/services/voice/reminder_parser.dart';
import 'package:lifeease/services/voice/voice_reminder_hints.dart';

void main() {
  late ReminderParser parser;
  late CommandProcessor processor;

  setUp(() {
    final now = DateTime(2026, 6, 2, 9);
    parser = ReminderParser(now: () => now);
    processor = CommandProcessor(reminderParser: parser);
  });

  void expectTime(ParsedReminderDraft draft, int hour, int minute) {
    expect(draft.scheduledAt.hour, hour);
    expect(draft.scheduledAt.minute, minute);
    expect(draft.hasExplicitTime, isTrue);
  }

  test('parses appointment reminder with flexible time', () {
    final draft = parser.parse(
      'Please add appointment reminder at 3:41 AM',
    );
    expect(draft, isNotNull);
    expect(draft!.title, 'Appointment');
    expectTime(draft, 3, 41);
  });

  test('parses doctor appointment with time', () {
    final draft = parser.parse(
      'Add reminder doctor appointment at 3:41 AM',
    );
    expect(draft, isNotNull);
    expect(draft!.title, 'Doctor appointment');
    expectTime(draft, 3, 41);
  });

  test('parses food and meal reminders with flexible time', () {
    for (final phrase in [
      'Add a reminder to eat lunch at 3:41 AM',
      'Please add food reminder at 3:05 PM',
      'Remind me to have dinner at 7:30 PM',
    ]) {
      final draft = parser.parse(phrase);
      expect(draft, isNotNull, reason: phrase);
      expect(draft!.hasExplicitTime, isTrue, reason: phrase);
      expect(draft.title, isNot(contains(' at 3')));
      expect(draft.title, isNot(contains(' at 7')));
    }
  });

  test('command processor flags flexible minute times as explicit', () {
    final result = processor.process(
      'Add reminder doctor appointment at 3:5 AM',
    );
    expect(result.intent, VoiceCommandIntent.createReminder);
    expect(result.reminderHasExplicitTime, isTrue);
    expect(result.reminderDraft!.scheduledAt.hour, 3);
    expect(result.reminderDraft!.scheduledAt.minute, 5);
  });

  test('does not strip Remind from add reminder remind me phrases', () {
    final draft = parser.parse(
      'Add reminder Remind me to take medicine tomorrow at 8 AM every day',
    );
    expect(draft, isNotNull);
    expect(draft!.title, 'Take medicine');
  });

  test('bare reminder with time uses Reminder title', () {
    final draft = parser.parse('Please add a reminder at 3:41 AM');
    expect(draft, isNotNull);
    expect(draft!.title, 'Reminder');
    expectTime(draft, 3, 41);
  });

  test('category is inferred from original phrase not title alone', () {
    expect(
      VoiceReminderHints.categoryForText(
        'Reminder Please add medicine reminder at 3:41 AM',
      ),
      'pill',
    );
    expect(
      VoiceReminderHints.categoryForText('Food add food reminder at 3:05 PM'),
      'food',
    );
  });

  test('implicit food and appointment phrases are recognized', () {
    for (final phrase in [
      'eat breakfast at 8:00 AM',
      'lunch at 12:30 PM',
      'doctor appointment at 3:41 AM',
    ]) {
      final result = processor.process(phrase);
      expect(result.intent, VoiceCommandIntent.createReminder, reason: phrase);
      expect(result.reminderHasExplicitTime, isTrue, reason: phrase);
    }
  });
}
