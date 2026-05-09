import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'inworld_tts_service.dart';
import 'whisper_api_service.dart';

class SpeechProcessingModule {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final WhisperApiService _whisper = WhisperApiService();
  final InworldTtsService _inworldTts = InworldTtsService();

  bool _isReady = false;
  final List<String> _transcriptHistory = [];

  List<String> get transcriptHistory => List.unmodifiable(_transcriptHistory);

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
    ValueChanged<String>? onLiveText,
  }) async {
    final ok = await initialize();
    if (!ok) return null;

    String captured = "";
    await _speech.listen(
      listenFor: listenFor,
      onResult: (result) {
        captured = result.recognizedWords;
        onLiveText?.call(captured);
      },
    );
    await Future<void>.delayed(listenFor + const Duration(milliseconds: 600));
    await _speech.stop();
    final clean = captured.trim();
    if (clean.isEmpty) return null;
    _transcriptHistory.insert(0, clean);
    if (_transcriptHistory.length > 20) _transcriptHistory.removeLast();
    return clean;
  }

  Future<WhisperTranscript> transcribeBatchAudio({
    required Uint8List audioBytes,
    required String fileName,
    String languageHint = 'en',
  }) async {
    final transcript = await _whisper.transcribeAudioBytes(
      audioBytes: audioBytes,
      fileName: fileName,
      languageHint: languageHint,
    );
    if (transcript.text.isNotEmpty) {
      _transcriptHistory.insert(0, transcript.text);
    }
    return transcript;
  }

  Future<void> speak(
    String text, {
    double speed = 0.48,
    double volume = 1.0,
  }) async {
    if (text.trim().isEmpty) return;
    final inworld = await _inworldTts.synthesize(
      text: text,
      speed: speed.clamp(0.5, 1.5),
      volume: volume.clamp(0.0, 1.0),
    );
    if (!inworld.usedFallback && inworld.audioBytes != null) {
      // The service is API-ready. Flutter playback of returned audio can be
      // wired to an audio player package when production dependencies allow it.
    }
    await initialize();
    await _tts.setSpeechRate(speed);
    await _tts.setVolume(volume);
    await _tts.stop();
    await _tts.speak(text);
  }
}
