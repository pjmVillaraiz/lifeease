import 'dart:typed_data';

import 'package:lifeease/services/speech/groq_service.dart';

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
  final GroqService _groq;

  WhisperApiService({GroqService? groq}) : _groq = groq ?? GroqService();

  bool get isConfigured => _groq.isConfigured;

  Future<WhisperTranscript> transcribeAudioBytes({
    required Uint8List audioBytes,
    required String fileName,
    String languageHint = 'en',
    int maxRetries = 2,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final transcript = await _groq.transcribeBytes(
          audioBytes: audioBytes,
          fileName: fileName,
        );
        if (transcript.text.trim().isNotEmpty) {
          return WhisperTranscript(
            text: transcript.text.trim(),
            language: languageHint,
          );
        }
      } on GroqTranscriptionException {
        if (attempt == maxRetries) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
    }

    return WhisperTranscript(text: '', language: 'unknown', usedFallback: true);
  }
}
