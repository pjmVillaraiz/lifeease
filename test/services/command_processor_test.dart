import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/services/voice/command_processor.dart';

void main() {
  group('CommandProcessor', () {
    test(
      'uses translated text before parsing Tagalog reminder commands',
      () async {
        final processor = CommandProcessor(
          translator: (_) async =>
              'Remind me to take medicine tomorrow at 8 AM every day',
        );

        final result = await processor.processAsync(
          'Paalalahanan mo ako uminom ng gamot bukas alas otso araw-araw',
        );

        expect(result.intent, VoiceCommandIntent.createReminder);
        expect(result.originalText, contains('Paalalahanan'));
        expect(result.reminderDraft, isNotNull);
        expect(result.reminderDraft!.title, 'Take medicine');
        expect(result.reminderDraft!.scheduledAt.hour, 8);
        expect(result.reminderDraft!.repeatType, 'daily');
      },
    );

    test(
      'falls back to local parsing when translation returns same text',
      () async {
        final processor = CommandProcessor(translator: (text) async => text);

        final result = await processor.processAsync(
          'Remind me to drink water at 2 PM',
        );

        expect(result.intent, VoiceCommandIntent.createReminder);
        expect(result.reminderDraft!.title, 'Drink water');
      },
    );
  });
}
