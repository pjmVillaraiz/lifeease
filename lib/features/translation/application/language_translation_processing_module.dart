import 'package:lifeease/core/services/backend/edge_ai_service.dart';

class TranslationResult {
  final String text;
  final String sourceLanguage;
  final String targetLanguage;
  final bool usedOfflineFallback;

  const TranslationResult({
    required this.text,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.usedOfflineFallback = false,
  });
}

class LanguageTranslationProcessingModule {
  final EdgeAiService _edgeAi;

  LanguageTranslationProcessingModule({EdgeAiService? edgeAi})
    : _edgeAi = edgeAi ?? EdgeAiService();

  static const Map<String, String> _enToTl = {
    'good morning': 'magandang umaga',
    'good afternoon': 'magandang hapon',
    'good evening': 'magandang gabi',
    'take medicine': 'uminom ng gamot',
    'take your medicine now': 'inumin mo na ang iyong gamot',
    'call emergency': 'tumawag sa emergency',
    'add reminder': 'magdagdag ng paalala',
    'how are you': 'kumusta ka',
  };

  static const Map<String, String> _tlToEn = {
    'magandang umaga': 'good morning',
    'magandang hapon': 'good afternoon',
    'magandang gabi': 'good evening',
    'uminom ng gamot': 'take medicine',
    'inumin mo na ang iyong gamot': 'take your medicine now',
    'tumawag sa emergency': 'call emergency',
    'magdagdag ng paalala': 'add reminder',
    'kumusta ka': 'how are you',
  };

  String translate({required String text, required bool toTagalog}) {
    final key = text.trim().toLowerCase();
    if (key.isEmpty) return '';
    if (toTagalog) return _enToTl[key] ?? text;
    return _tlToEn[key] ?? text;
  }

  Future<TranslationResult> translateAsync({
    required String text,
    required bool toTagalog,
  }) async {
    final target = toTagalog ? 'tl' : 'en';
    final source = detectLanguage(text);
    if (!_edgeAi.isConfigured || text.trim().isEmpty) {
      return TranslationResult(
        text: translate(text: text, toTagalog: toTagalog),
        sourceLanguage: source,
        targetLanguage: target,
        usedOfflineFallback: true,
      );
    }

    try {
      final translated = await _edgeAi.translate(
        text: text,
        targetLanguage: target,
        sourceLanguage: source,
      );
      return TranslationResult(
        text: translated ?? translate(text: text, toTagalog: toTagalog),
        sourceLanguage: source,
        targetLanguage: target,
        usedOfflineFallback: translated == null,
      );
    } catch (_) {
      return TranslationResult(
        text: translate(text: text, toTagalog: toTagalog),
        sourceLanguage: source,
        targetLanguage: target,
        usedOfflineFallback: true,
      );
    }
  }

  String detectLanguage(String text) {
    final normalized = text.toLowerCase();
    final tagalogHits = [
      'gamot',
      'paalala',
      'kumusta',
      'inumin',
      'tumawag',
      'araw',
    ].where(normalized.contains).length;
    final englishHits = [
      'medicine',
      'reminder',
      'call',
      'appointment',
      'today',
      'daily',
    ].where(normalized.contains).length;
    if (tagalogHits > 0 && englishHits > 0) return 'mixed';
    if (tagalogHits > englishHits) return 'tl';
    return 'en';
  }
}
