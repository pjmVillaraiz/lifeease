import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifeease/core/services/supabase_config.dart';

class EdgeAiService {
  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  bool get isConfigured => SupabaseConfig.isInitialized;

  Future<String?> transcribeAudio({
    required Uint8List audioBytes,
    required String fileName,
    String languageHint = 'en',
  }) async {
    final response = await _invoke('ai', {
      'action': 'transcribe',
      'fileName': fileName,
      'languageHint': languageHint,
      'audioBase64': audioBytes.toList(),
    });
    return response?['text'] as String?;
  }

  Future<Map<String, dynamic>?> processCommand(String text) async {
    return _invoke('ai', {'action': 'nlp', 'text': text});
  }

  Future<String?> translate({
    required String text,
    required String targetLanguage,
    required String sourceLanguage,
  }) async {
    final response = await _invoke('ai', {
      'action': 'translate',
      'text': text,
      'targetLanguage': targetLanguage,
      'sourceLanguage': sourceLanguage,
    });
    return response?['text'] as String?;
  }

  Future<Uint8List?> synthesizeSpeech({
    required String text,
    double speed = 0.95,
    double volume = 1.0,
  }) async {
    final response = await _invoke('ai', {
      'action': 'tts',
      'text': text,
      'speed': speed,
      'volume': volume,
    });
    final audio = response?['audioBytes'] as List<dynamic>?;
    if (audio == null) return null;
    return Uint8List.fromList(audio.cast<int>());
  }

  Future<Map<String, dynamic>?> _invoke(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client.functions.invoke(functionName, body: body);
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }
}
