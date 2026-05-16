import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:lifeease/shared/providers/language_controller.dart';
import 'package:lifeease/shared/providers/settings_controller.dart';

enum AppSpeechLanguage {
  english(code: 'en', preferredLocales: ['en-US', 'en-GB', 'en']),
  tagalog(code: 'tl', preferredLocales: ['fil-PH', 'tl-PH', 'fil', 'tl']);

  const AppSpeechLanguage({required this.code, required this.preferredLocales});

  final String code;
  final List<String> preferredLocales;
}

class TtsLanguageService {
  const TtsLanguageService._();

  static AppSpeechLanguage get currentLanguage {
    try {
      return SettingsController.instance.tagalog
          ? AppSpeechLanguage.tagalog
          : AppSpeechLanguage.english;
    } catch (_) {
      return LanguageController.isTagalog.value
          ? AppSpeechLanguage.tagalog
          : AppSpeechLanguage.english;
    }
  }

  static Future<void> applyCurrentLanguage(FlutterTts tts) {
    return applyLanguage(tts, currentLanguage);
  }

  static Future<void> applyLanguage(
    FlutterTts tts,
    AppSpeechLanguage language,
  ) async {
    final selectedLocale = await _bestAvailableLocaleFor(tts, language);
    if (selectedLocale != null) {
      await tts.setLanguage(selectedLocale);
      debugPrint('TTS language selected: $selectedLocale');
    }

    final selectedVoice = await _bestVoiceFor(
      tts,
      language,
      selectedLocale: selectedLocale,
    );
    if (selectedVoice != null) {
      await tts.setVoice(selectedVoice);
      debugPrint(
        'TTS voice selected: ${selectedVoice['name']} '
        '(${selectedVoice['locale']}).',
      );
      return;
    }

    for (final locale in language.preferredLocales) {
      if (await _trySetLanguage(tts, locale)) return;
    }

    if (language != AppSpeechLanguage.english) {
      await applyLanguage(tts, AppSpeechLanguage.english);
    }
  }

  static String reminderLabel() {
    return currentLanguage == AppSpeechLanguage.tagalog
        ? 'Paalala'
        : 'Reminder';
  }

  static String descriptionLabel() {
    return currentLanguage == AppSpeechLanguage.tagalog ? 'Tala' : 'Note';
  }

  static String doneActionLabel() {
    return currentLanguage == AppSpeechLanguage.tagalog ? 'Tapos' : 'Done';
  }

  static String skipActionLabel() {
    return currentLanguage == AppSpeechLanguage.tagalog ? 'Laktawan' : 'Skip';
  }

  static String canceledLabel() {
    return currentLanguage == AppSpeechLanguage.tagalog
        ? 'Hindi aktibo'
        : 'Inactive';
  }

  static String notificationTitle() {
    return currentLanguage == AppSpeechLanguage.tagalog
        ? 'LifeEase Paalala'
        : 'LifeEase Reminder';
  }

  static String reminderSpeech(String title, String description) {
    final cleanTitle = title.trim();
    final cleanDescription = description.trim();
    if (currentLanguage == AppSpeechLanguage.tagalog) {
      final body = cleanTitle.isEmpty
          ? 'May paalala ka ngayon'
          : _tagalogReminderBody(cleanTitle);
      if (cleanDescription.isEmpty) return 'Paalala: $body.';
      return 'Paalala: $body. Tala: $cleanDescription.';
    }

    final body = cleanTitle.isEmpty
        ? 'You have a reminder now'
        : _englishReminderBody(cleanTitle);
    if (cleanDescription.isEmpty) return 'Reminder: $body.';
    return 'Reminder: $body. Note: $cleanDescription.';
  }

  static String _englishReminderBody(String title) {
    final lower = title.toLowerCase();
    if (lower.startsWith('take ') ||
        lower.startsWith('drink ') ||
        lower.startsWith('eat ') ||
        lower.startsWith('call ') ||
        lower.startsWith('go ') ||
        lower.startsWith('check ')) {
      return '$title now';
    }
    return title;
  }

  static String _tagalogReminderBody(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('gamot') || lower.contains('medicine')) {
      return 'Inumin mo na ang iyong gamot';
    }
    if (lower.startsWith('uminom') ||
        lower.startsWith('inumin') ||
        lower.startsWith('kumain') ||
        lower.startsWith('tawagan') ||
        lower.startsWith('pumunta')) {
      return '$title na';
    }
    return title;
  }

  static Future<String?> _bestAvailableLocaleFor(
    FlutterTts tts,
    AppSpeechLanguage language,
  ) async {
    final languages = await _availableLanguages(tts);
    for (final preferredLocale in language.preferredLocales) {
      final normalizedPreferred = _normalize(preferredLocale);
      if (languages.contains(normalizedPreferred)) return preferredLocale;
    }

    for (final preferredLocale in language.preferredLocales) {
      final preferredCode = _normalize(preferredLocale).split('-').first;
      for (final language in languages) {
        if (language.split('-').first == preferredCode) return language;
      }
    }

    for (final preferredLocale in language.preferredLocales) {
      if (await _isLanguageAvailable(tts, preferredLocale)) {
        return preferredLocale;
      }
    }

    return null;
  }

  static Future<Map<String, String>?> _bestVoiceFor(
    FlutterTts tts,
    AppSpeechLanguage language, {
    String? selectedLocale,
  }) async {
    try {
      final voices = await tts.getVoices;
      if (voices is! List) return null;

      if (selectedLocale != null) {
        final normalizedSelected = _normalize(selectedLocale);
        for (final voice in voices) {
          final voiceMap = _voiceMapFrom(voice);
          if (voiceMap == null) continue;

          final locale = _normalize(voiceMap['locale']);
          if (locale == normalizedSelected) return voiceMap;
        }
      }

      for (final preferredLocale in language.preferredLocales) {
        final normalizedLocale = _normalize(preferredLocale);
        for (final voice in voices) {
          final voiceMap = _voiceMapFrom(voice);
          if (voiceMap == null) continue;

          final locale = _normalize(voiceMap['locale']);
          final name = _normalize(voiceMap['name']);
          if (locale == normalizedLocale || name.contains(normalizedLocale)) {
            return voiceMap;
          }
        }
      }

      for (final preferredLocale in language.preferredLocales) {
        final languageCode = _normalize(preferredLocale).split('-').first;
        for (final voice in voices) {
          final voiceMap = _voiceMapFrom(voice);
          if (voiceMap == null) continue;

          final locale = _normalize(voiceMap['locale']);
          if (locale.split('-').first == languageCode) {
            return voiceMap;
          }
        }
      }
    } catch (error) {
      debugPrint('TTS voice lookup failed: $error');
    }

    return null;
  }

  static Map<String, String>? _voiceMapFrom(Object? voice) {
    if (voice is! Map) return null;

    final name = voice['name']?.toString();
    final locale = voice['locale']?.toString();
    if (name == null || locale == null) return null;

    return {'name': name, 'locale': locale};
  }

  static Future<Set<String>> _availableLanguages(FlutterTts tts) async {
    try {
      final languages = await tts.getLanguages;
      if (languages is! List) return const {};
      return languages
          .map((language) => _normalize(language?.toString()))
          .where((language) => language.isNotEmpty)
          .toSet();
    } catch (error) {
      debugPrint('TTS language lookup failed: $error');
      return const {};
    }
  }

  static Future<bool> _isLanguageAvailable(
    FlutterTts tts,
    String locale,
  ) async {
    try {
      final result = await tts.isLanguageAvailable(locale);
      if (result is bool) return result;
      if (result is int) return result == 1;
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _trySetLanguage(FlutterTts tts, String locale) async {
    try {
      final result = await tts.setLanguage(locale);
      if (result is bool) return result;
      if (result is int) return result == 1;
      return result != null;
    } catch (_) {
      return false;
    }
  }

  static String _normalize(String? value) {
    return (value ?? '').replaceAll('_', '-').toLowerCase().trim();
  }
}
