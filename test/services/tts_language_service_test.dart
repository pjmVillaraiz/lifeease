import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/shared/providers/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsLanguageService Speech Formatting', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsController.load();
    });

    test('generates correct English phrasing', () {
      SettingsController.instance.updateTagalog(false);

      final speech = TtsLanguageService.reminderSpeech(
        'Taking Medicine',
        'Take after lunch.',
      );

      expect(speech, "It's time to take your medicine. Take after lunch.");
    });

    test('generates correct Tagalog phrasing', () {
      SettingsController.instance.updateTagalog(true);

      final speech = TtsLanguageService.reminderSpeech(
        'Taking Medicine',
        'inumin pagkatapos kumain',
      );

      expect(speech, "Oras na para inumin ang iyong gamot. inumin pagkatapos kumain.");
    });

    test('generates correct Taglish phrasing', () {
      SettingsController.instance.updateTagalog(true);

      final speech = TtsLanguageService.reminderSpeech(
        'Taking Medicine',
        'Take after lunch.',
      );

      expect(speech, "Oras na para mag-take ng medicine. Take after lunch.");
    });
  });
}
