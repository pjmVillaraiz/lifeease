import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechProcessingModule {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isReady = false;

  Future<bool> initialize() async {
    if (_isReady) return true;
    final available = await _speech.initialize();
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    _isReady = available;
    return available;
  }

  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 6),
  }) async {
    final ok = await initialize();
    if (!ok) return null;

    String captured = "";
    await _speech.listen(
      listenFor: listenFor,
      onResult: (result) {
        captured = result.recognizedWords;
      },
    );
    await Future<void>.delayed(listenFor + const Duration(milliseconds: 600));
    await _speech.stop();
    return captured.trim().isEmpty ? null : captured.trim();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await initialize();
    await _tts.stop();
    await _tts.speak(text);
  }
}
