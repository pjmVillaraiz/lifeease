import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/services/voice/reminder_parser.dart';

void main() {
  late ReminderParser parser;

  setUp(() {
    parser = ReminderParser(now: () => DateTime(2026, 6, 2, 9));
  });

  test('extracts title and time from English reminder', () {
    final draft = parser.parse('Remind me to drink water at 2 PM');

    expect(draft, isNotNull);
    expect(draft!.title, 'Drink water');
    expect(draft.scheduledAt.year, 2026);
    expect(draft.scheduledAt.month, 6);
    expect(draft.scheduledAt.day, 2);
    expect(draft.scheduledAt.hour, 14);
    expect(draft.scheduledAt.minute, 0);
    expect(draft.repeatType, 'none');
  });

  test('extracts tomorrow date and morning time', () {
    final draft = parser.parse('Remind me to take medicine tomorrow at 8 AM');

    expect(draft, isNotNull);
    expect(draft!.title, 'Take medicine');
    expect(draft.scheduledAt.day, 3);
    expect(draft.scheduledAt.hour, 8);
  });

  test('extracts today date from add reminder command', () {
    final draft = parser.parse('Add reminder doctor appointment today at 3 PM');

    expect(draft, isNotNull);
    expect(draft!.title, 'Doctor appointment');
    expect(draft.hasExplicitDate, isTrue);
    expect(draft.scheduledAt.day, 2);
    expect(draft.scheduledAt.hour, 15);
  });

  test('extracts hourly frequency from English command', () {
    final draft = parser.parse('Remind me to drink water every hour');

    expect(draft, isNotNull);
    expect(draft!.title, 'Drink water');
    expect(draft.frequency, 'every_hour');
    expect(draft.repeatType, 'custom:60');
    expect(draft.repeatIntervalMinutes, 60);
  });

  test('extracts daily frequency from Taglish command', () {
    final draft = parser.parse('Remind me to take vitamins araw-araw');

    expect(draft, isNotNull);
    expect(draft!.title, 'Take vitamins');
    expect(draft.frequency, 'daily');
    expect(draft.repeatType, 'daily');
  });

  test('extracts Tagalog reminder with bukas and kada oras', () {
    final draft = parser.parse(
      'Paalalahanan mo ako uminom ng gamot bukas ng 8 AM kada oras',
    );

    expect(draft, isNotNull);
    expect(draft!.title, 'Uminom ng gamot');
    expect(draft.scheduledAt.day, 3);
    expect(draft.scheduledAt.hour, 8);
    expect(draft.frequency, 'every_hour');
  });

  test('extracts morning and evening frequency', () {
    final draft = parser.parse(
      'Remind me to take medicine at 7 AM morning and evening',
    );

    expect(draft, isNotNull);
    expect(draft!.title, 'Take medicine');
    expect(draft.frequency, 'morning_evening');
    expect(draft.repeatType, 'custom:720');
  });

  test('extracts custom hourly interval', () {
    final draft = parser.parse('Add reminder drink water every 3 hours');

    expect(draft, isNotNull);
    expect(draft!.title, 'Drink water');
    expect(draft.frequency, 'custom_3_hours');
    expect(draft.repeatType, 'custom:180');
    expect(draft.repeatIntervalMinutes, 180);
  });
}
