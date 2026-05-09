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
  });
}
