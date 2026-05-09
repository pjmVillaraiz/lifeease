enum LightweightNlpModel { gemma2bIt, mobileBertIntent }

enum VoiceIntentType {
  addReminder,
  callEmergency,
  translate,
  summarize,
  unknown,
}

class VoiceIntentResult {
  final VoiceIntentType type;
  final String normalizedText;
  final String summary;
  final String intent;
  final String task;
  final String? time;
  final String? repeat;
  final double confidence;
  final List<String> detectedKeywords;
  final LightweightNlpModel recommendedPrimaryModel;
  final LightweightNlpModel recommendedSecondaryModel;

  const VoiceIntentResult({
    required this.type,
    required this.normalizedText,
    required this.summary,
    required this.intent,
    required this.task,
    required this.time,
    required this.repeat,
    required this.confidence,
    required this.detectedKeywords,
    required this.recommendedPrimaryModel,
    required this.recommendedSecondaryModel,
  });

  Map<String, dynamic> toJson() => {
    'intent': intent,
    'task': task,
    'time': time,
    'repeat': repeat,
    'confidence': confidence,
    'keywords': detectedKeywords,
  };
}

class VoiceCommandProcessingModule {
  static const List<String> _keywords = [
    'medicine',
    'gamot',
    'appointment',
    'check-up',
    'reminder',
    'paalala',
    'emergency',
    'call',
    'alarm',
    'task',
  ];

  Future<VoiceIntentResult> parseAsync(String rawText) async {
    return Future<VoiceIntentResult>.microtask(() => parse(rawText));
  }

  VoiceIntentResult parse(String rawText) {
    final text = rawText.trim().toLowerCase();
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
    final type = _detectIntent(normalized);
    final keywords = _keywords.where(normalized.contains).toList();
    final time = _extractTime(normalized);

    return VoiceIntentResult(
      type: type,
      normalizedText: normalized,
      summary: summarizeText(rawText),
      intent: _intentName(type),
      task: _extractTask(rawText, normalized),
      time: time,
      repeat: _extractRepeat(normalized),
      confidence: _confidence(type, keywords, time),
      detectedKeywords: keywords,
      recommendedPrimaryModel: LightweightNlpModel.gemma2bIt,
      recommendedSecondaryModel: LightweightNlpModel.mobileBertIntent,
    );
  }

  String summarizeText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final sentences = trimmed.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length == 1) {
      return trimmed.length <= 90 ? trimmed : '${trimmed.substring(0, 87)}...';
    }
    return '${sentences.first} ${sentences.last}'.trim();
  }

  String _extractTask(String rawText, String normalized) {
    if (normalized.isEmpty) return '';
    var task = rawText.trim();
    final cleanupPatterns = [
      RegExp(r'please\s+', caseSensitive: false),
      RegExp(r'remind me to\s+', caseSensitive: false),
      RegExp(r'add (a )?reminder to\s+', caseSensitive: false),
      RegExp(r'set (an )?alarm to\s+', caseSensitive: false),
      RegExp(r'every day.*$', caseSensitive: false),
      RegExp(r'daily.*$', caseSensitive: false),
      RegExp(r'at\s+\d{1,2}(:\d{2})?\s*(am|pm).*$', caseSensitive: false),
      RegExp(r'after\s+(breakfast|lunch|dinner).*$', caseSensitive: false),
    ];
    for (final pattern in cleanupPatterns) {
      task = task.replaceAll(pattern, '');
    }
    task = task.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (task.isEmpty && normalized.contains('medicine')) return 'Take medicine';
    if (task.isEmpty && normalized.contains('gamot')) return 'Uminom ng gamot';
    return task.isEmpty ? summarizeText(rawText) : _capitalize(task);
  }

  String? _extractTime(String text) {
    final match = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    ).firstMatch(text);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    final suffix = (match.group(3) ?? '').toUpperCase();
    if (hour == null) return null;
    return '${hour.clamp(1, 12)}:${minute.toString().padLeft(2, '0')} $suffix';
  }

  String? _extractRepeat(String text) {
    if (text.contains('every day') ||
        text.contains('daily') ||
        text.contains('araw-araw')) {
      return 'daily';
    }
    if (text.contains('weekly') || text.contains('every week')) return 'weekly';
    if (text.contains('monthly') || text.contains('every month')) {
      return 'monthly';
    }
    return null;
  }

  double _confidence(
    VoiceIntentType type,
    List<String> keywords,
    String? time,
  ) {
    if (type == VoiceIntentType.unknown) return 0.2;
    var score = 0.55 + (keywords.length * 0.08);
    if (time != null) score += 0.15;
    return score.clamp(0.0, 0.96);
  }

  String _intentName(VoiceIntentType type) {
    switch (type) {
      case VoiceIntentType.addReminder:
        return 'create_reminder';
      case VoiceIntentType.callEmergency:
        return 'call_emergency';
      case VoiceIntentType.translate:
        return 'translate';
      case VoiceIntentType.summarize:
        return 'summarize';
      case VoiceIntentType.unknown:
        return 'unknown';
    }
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  VoiceIntentType _detectIntent(String text) {
    if (text.contains('add reminder') ||
        text.contains('remind me') ||
        text.contains('schedule') ||
        text.contains('paalala') ||
        text.contains('alarm')) {
      return VoiceIntentType.addReminder;
    }
    if (text.contains('call') ||
        text.contains('emergency') ||
        text.contains('dial')) {
      return VoiceIntentType.callEmergency;
    }
    if (text.contains('translate') ||
        text.contains('tagalog') ||
        text.contains('english')) {
      return VoiceIntentType.translate;
    }
    if (text.contains('summarize') || text.contains('summary')) {
      return VoiceIntentType.summarize;
    }
    return VoiceIntentType.unknown;
  }
}
