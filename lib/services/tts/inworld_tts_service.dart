import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lifeease/core/services/backend/edge_ai_service.dart';
import 'package:lifeease/core/services/tts/tts_language_service.dart';

class InworldTtsService {
  final EdgeAiService _edgeAi = EdgeAiService();
  static const MethodChannel _channel = MethodChannel('lifeease/reminder_native');

  Future<String?> generateSpeechFile(String text, String id, {String? languageCode}) async {
    if (text.trim().isEmpty || id.trim().isEmpty) return null;
    try {
      final audioBytes = await _edgeAi.synthesizeSpeech(
        text: text,
        speed: 0.95,
        volume: 1.0,
        language: languageCode ?? TtsLanguageService.currentLanguage.code,
      );
      if (audioBytes == null || audioBytes.isEmpty) return null;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/tts_$id.mp3');
      await file.writeAsBytes(audioBytes);
      debugPrint('Generated Inworld TTS file for $id: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('Error generating Inworld TTS speech file: $e');
      return null;
    }
  }

  Future<bool> playAudio(String filePath) async {
    try {
      await _channel.invokeMethod<void>('playAudioFile', {'filePath': filePath});
      return true;
    } catch (e) {
      debugPrint('Error playing audio via native player: $e');
      return false;
    }
  }

  Future<void> stopAudio() async {
    try {
      await _channel.invokeMethod<void>('stopAudio');
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }
}
