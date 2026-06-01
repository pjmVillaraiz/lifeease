import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:lifeease/core/services/tts/tts_language_service.dart';

import 'inworld_tts_service.dart';
import 'whisper_api_service.dart';

class SpeechProcessingModule {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final WhisperApiService _whisper = WhisperApiService();
  final InworldTtsService _inworldTts = InworldTtsService();

  bool _isSpeechReady = false;
  bool _isTtsReady = false;
  bool _cancelRequested = false;
  final List<String> _transcriptHistory = [];

  List<String> get transcriptHistory => List.unmodifiable(_transcriptHistory);

  Future<bool> initialize() async {
    final speechReady = await _initializeSpeech();
    await _initializeTts();
    return speechReady;
  }

  Future<bool> _initializeSpeech() async {
    if (_isSpeechReady) return true;
    final available = await _speech.initialize(
      onError: (error) => debugPrint('Speech recognition error: $error'),
      onStatus: (status) => debugPrint('Speech recognition status: $status'),
    );
    _isSpeechReady = available;
    return available;
  }

  Future<void> _initializeTts() async {
    if (_isTtsReady) return;
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await TtsLanguageService.applyCurrentLanguage(_tts);
    _isTtsReady = true;
  }

  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 6),
    ValueChanged<String>? onLiveText,
  }) async {
    final ok = await _initializeSpeech();
    if (!ok) return null;
    _cancelRequested = false;
    if (_speech.isListening) {
      await _speech.stop();
    }

    String captured = "";
    await _speech.listen(
      listenFor: listenFor,
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (result) {
        captured = result.recognizedWords;
        onLiveText?.call(captured);
      },
    );
    final startedAt = DateTime.now();
    while (!_cancelRequested &&
        DateTime.now().difference(startedAt) <
            listenFor + const Duration(milliseconds: 600)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (_cancelRequested) {
      await _speech.cancel();
      _cancelRequested = false;
      return null;
    }
    await _speech.stop();
    final clean = captured.trim();
    if (clean.isEmpty) return null;
    _transcriptHistory.insert(0, clean);
    if (_transcriptHistory.length > 20) _transcriptHistory.removeLast();
    return clean;
  }

  Future<void> cancelListening() async {
    _cancelRequested = true;
    if (_speech.isListening) {
      await _speech.cancel();
    }
    await _speech.stop();
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
    await _initializeTts();
    await _tts.setSpeechRate(speed);
    await _tts.setVolume(volume);
    await TtsLanguageService.applyCurrentLanguage(_tts);
    await _tts.stop();
    await _tts.speak(text);
  }
}
