import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/features/voice/application/voice_command_processing_module.dart';
import 'package:lifeease/services/voice/command_processor.dart';

class _FakeGemmaNlpModule extends VoiceCommandProcessingModule {
  _FakeGemmaNlpModule(this._result);

  final VoiceIntentResult _result;

  @override
  bool get isGemmaAvailable => true;

  @override
  Future<VoiceIntentResult> parseAsync(String rawText) async => _result;
}

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

    test('uses Gemma NLP result when configured', () async {
      final processor = CommandProcessor(
        nlpModule: _FakeGemmaNlpModule(
          VoiceIntentResult(
            type: VoiceIntentType.addReminder,
            normalizedText: 'remind me to take medicine at 8 am daily',
            summary: 'Take medicine at 8 AM daily',
            intent: 'create_reminder',
            task: 'Take medicine',
            time: '8:00 AM',
            repeat: 'daily',
            confidence: 0.91,
            detectedKeywords: const ['medicine'],
            recommendedPrimaryModel: LightweightNlpModel.gemma2bIt,
            recommendedSecondaryModel: LightweightNlpModel.mobileBertIntent,
            modelUsed: 'gemma-2-2b-it',
            usedGemma: true,
          ),
        ),
      );

      final result = await processor.processAsync(
        'Remind me to take medicine at 8 AM every day',
      );

      expect(result.intent, VoiceCommandIntent.createReminder);
      expect(result.reminderDraft, isNotNull);
      expect(result.reminderDraft!.title, 'Take medicine');
      expect(result.reminderHasExplicitTime, isTrue);
      expect(result.usedGemma, isTrue);
      expect(result.nlpModelUsed, 'gemma-2-2b-it');
    });
  });
}
