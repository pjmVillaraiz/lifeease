import 'dart:typed_data';

import 'package:lifeease/core/services/backend/edge_ai_service.dart';

class WhisperTranscript {
  final String text;
  final String language;
  final bool usedFallback;

  const WhisperTranscript({
    required this.text,
    required this.language,
    this.usedFallback = false,
  });
}

class WhisperApiService {
  final EdgeAiService _edgeAi;

  WhisperApiService({EdgeAiService? edgeAi})
    : _edgeAi = edgeAi ?? EdgeAiService();

  bool get isConfigured => _edgeAi.isConfigured;

  Future<WhisperTranscript> transcribeAudioBytes({
    required Uint8List audioBytes,
    required String fileName,
    String languageHint = 'en',
    int maxRetries = 2,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final text = await _edgeAi.transcribeAudio(
        audioBytes: audioBytes,
        fileName: fileName,
        languageHint: languageHint,
      );
      if (text != null && text.trim().isNotEmpty) {
        return WhisperTranscript(text: text.trim(), language: languageHint);
      }
      await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
    }

    return WhisperTranscript(text: '', language: 'unknown', usedFallback: true);
  }
}
