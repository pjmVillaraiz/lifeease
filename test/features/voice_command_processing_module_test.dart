import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/features/voice/application/voice_command_processing_module.dart';

void main() {
  group('VoiceCommandProcessingModule', () {
    test('parses reminder intent with time and repeat', () {
      final module = VoiceCommandProcessingModule();

      final result = module.parse(
        'Please remind me to take medicine at 8 AM every day',
      );

      expect(result.type, VoiceIntentType.addReminder);
      expect(result.time, '8:00 AM');
      expect(result.repeat, 'daily');
      expect(result.task.toLowerCase(), contains('take medicine'));
    });

    test('detects emergency command', () {
      final module = VoiceCommandProcessingModule();

      final result = module.parse('Call emergency contact');

      expect(result.type, VoiceIntentType.callEmergency);
      expect(result.intent, 'call_emergency');
    });

    test('parses Tagalog reminder intent with repeat', () {
      final module = VoiceCommandProcessingModule();

      final result = module.parse(
        'Magdagdag ng paalala uminom ng gamot araw-araw',
      );

      expect(result.type, VoiceIntentType.addReminder);
      expect(result.repeat, 'daily');
      expect(result.detectedKeywords, contains('gamot'));
    });

    test('summarizes long spoken command text', () {
      final module = VoiceCommandProcessingModule();

      final summary = module.summarizeText(
        'Please summarize this command because it contains a lot of spoken details about medicine, appointments, hydration, and daily safety checks.',
      );

      expect(summary.length, lessThanOrEqualTo(90));
      expect(summary, endsWith('...'));
    });

    test('detects Tagalog emergency intent locally', () {
      final module = VoiceCommandProcessingModule();

      final result = module.parse('Tumawag ng emergency contact');

      expect(result.type, VoiceIntentType.callEmergency);
      expect(result.usedGemma, isFalse);
      expect(result.modelUsed, 'gemma-2-lightweight-local-fallback');
    });
  });
}
