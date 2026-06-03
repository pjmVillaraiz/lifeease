import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:lifeease/core/constants/env_config.dart';

class GoogleTranslationService {
  final http.Client _client;

  GoogleTranslationService({http.Client? client}) : _client = client ?? http.Client();

  /// Translates Tagalog or Taglish reminder commands to standard English.
  Future<String> translateToEnglish(String text) async {
    final apiKey = EnvConfig.cloudTranslationApiKey;
    if (apiKey == null || EnvConfig.isPlaceholder(apiKey)) {
      // Fallback: If translation API is not configured, return the raw input
      return text;
    }

    if (_isPureEnglish(text)) {
      return text;
    }

    try {
      final url = Uri.parse('https://translation.googleapis.com/language/translate/v2?key=$apiKey');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'target': 'en',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translations = data['data']?['translations'] as List?;
        if (translations != null && translations.isNotEmpty) {
          final translatedText = translations[0]['translatedText']?.toString() ?? text;
          return _unescapeHtml(translatedText);
        }
      }
      return text;
    } catch (_) {
      return text;
    }
  }

  /// Simple check to see if the command might contain Tagalog/Taglish.
  bool _isPureEnglish(String text) {
    final clean = text.toLowerCase().trim();
    // Common Tagalog or Taglish command fragments
    final filipinoWords = [
      'paalala', 'paalalahanan', 'ako', 'mo', 'uminom', 'gamot', 'alas', 'mamaya',
      'bukas', 'ngayon', 'oras', 'salamat', 'opo', 'oho', 'po', 'kain', 'tawag',
      'gabi', 'umaga', 'hapon', 'tanghali', 'susi', 'pinto', 'patay', 'bukas'
    ];
    return !filipinoWords.any((word) => clean.contains(word));
  }

  /// Unescape HTML character entities returned by the translation API.
  String _unescapeHtml(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}
