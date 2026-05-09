import 'dart:typed_data';

import 'package:lifeease/core/services/backend/edge_ai_service.dart';

class InworldTtsResult {
  final Uint8List? audioBytes;
  final Duration latency;
  final bool usedFallback;

  const InworldTtsResult({
    required this.audioBytes,
    required this.latency,
    this.usedFallback = false,
  });
}

class InworldTtsService {
  final EdgeAiService _edgeAi;

  InworldTtsService({EdgeAiService? edgeAi})
    : _edgeAi = edgeAi ?? EdgeAiService();

  bool get isConfigured => _edgeAi.isConfigured;

  Future<InworldTtsResult> synthesize({
    required String text,
    double speed = 0.95,
    double volume = 1.0,
    String voice = 'friendly_elder_child_safe',
  }) async {
    final started = DateTime.now();

    if (!_edgeAi.isConfigured || text.trim().isEmpty) {
      return InworldTtsResult(
        audioBytes: null,
        latency: DateTime.now().difference(started),
        usedFallback: true,
      );
    }

    try {
      final audio = await _edgeAi.synthesizeSpeech(
        text: text,
        speed: speed,
        volume: volume,
      );

      return InworldTtsResult(
        audioBytes: audio,
        latency: DateTime.now().difference(started),
        usedFallback: audio == null,
      );
    } catch (_) {
      return InworldTtsResult(
        audioBytes: null,
        latency: DateTime.now().difference(started),
        usedFallback: true,
      );
    }
  }
}
