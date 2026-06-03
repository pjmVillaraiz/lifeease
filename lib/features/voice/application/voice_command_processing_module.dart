import 'package:lifeease/core/services/backend/edge_ai_service.dart';
import 'package:lifeease/features/voice/application/gemma_nlp_service.dart';
import 'package:lifeease/services/voice/voice_time_parser.dart';

enum LightweightNlpModel { gemma2bIt, mobileBertIntent }

enum VoiceIntentType {
  addReminder,
  callEmergency,
  translate,
  summarize,
  reminderList,
  dailySchedule,
  navigation,
  statistics,
  internet,
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
  final String? modelUsed;
  final bool usedGemma;
  final String? nlpFailureReason;

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
    this.modelUsed,
    this.usedGemma = false,
    this.nlpFailureReason,
  });

  Map<String, dynamic> toJson() => {
    'intent': intent,
    'task': task,
    'summary': summary,
    'time': time,
    'repeat': repeat,
    'confidence': confidence,
    'keywords': detectedKeywords,
    if (modelUsed != null) 'model': modelUsed,
    'usedGemma': usedGemma,
  };
}

class VoiceCommandProcessingModule {
  VoiceCommandProcessingModule({
    EdgeAiService? edgeAi,
    GemmaNlpService? gemmaNlp,
  }) : _edgeAi = edgeAi ?? EdgeAiService(),
       _gemmaNlp = gemmaNlp ?? GemmaNlpService();

  final EdgeAiService _edgeAi;
  final GemmaNlpService _gemmaNlp;

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
    'uminom',
    'water',
    'tubig',
  ];

  bool get isGemmaAvailable => _gemmaNlp.isAvailable || _edgeAi.isConfigured;

  /// Parses spoken command text using Gemma 2 when available, with local fallback.
  Future<VoiceIntentResult> parseAsync(String rawText) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return parse(trimmed);
    }

    String? gemmaFailureReason;

    if (_gemmaNlp.isAvailable) {
      final gemmaResult = await _gemmaNlp.parseCommand(trimmed);
      final parsed = _fromRemoteResult(
        trimmed,
        gemmaResult.data,
        usedGemma: true,
      );
      if (parsed != null) return parsed;
      gemmaFailureReason = gemmaResult.errorMessage ?? _gemmaNlp.lastErrorMessage;
    }

    if (_edgeAi.isConfigured) {
      final remote = await _edgeAi.processCommand(trimmed);
      final parsed = _fromRemoteResult(trimmed, remote, usedGemma: true);
      if (parsed != null) return parsed;
      gemmaFailureReason ??= 'Supabase edge AI did not return a Gemma result.';
    }

    return parse(trimmed, nlpFailureReason: gemmaFailureReason);
  }

  VoiceIntentResult parse(String rawText, {String? nlpFailureReason}) {
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
      modelUsed: 'gemma-2-lightweight-local-fallback',
      usedGemma: false,
      nlpFailureReason: nlpFailureReason,
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
      RegExp(r'paalalahanan mo ako\s+', caseSensitive: false),
      RegExp(r'magdagdag ng paalala\s+', caseSensitive: false),
      RegExp(r'every day.*$', caseSensitive: false),
      RegExp(r'daily.*$', caseSensitive: false),
      RegExp(r'araw-araw.*$', caseSensitive: false),
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
    final parsed = VoiceTimeParser.parse(text);
    if (parsed == null) return null;
    var displayHour = parsed.hour;
    final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
    if (displayHour == 0) {
      displayHour = 12;
    } else if (displayHour > 12) {
      displayHour -= 12;
    }
    return '$displayHour:${parsed.minute.toString().padLeft(2, '0')} $suffix';
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
      case VoiceIntentType.reminderList:
        return 'reminder_list';
      case VoiceIntentType.dailySchedule:
        return 'daily_schedule';
      case VoiceIntentType.navigation:
        return 'navigation';
      case VoiceIntentType.statistics:
        return 'statistics';
      case VoiceIntentType.internet:
        return 'internet_query';
      case VoiceIntentType.unknown:
        return 'unknown';
    }
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  VoiceIntentResult? _fromRemoteResult(
    String rawText,
    Map<String, dynamic>? data, {
    required bool usedGemma,
  }) {
    if (data == null || data['usedFallback'] == true) return null;

    final normalized = rawText.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final intent = data['intent']?.toString() ?? 'unknown';
    final type = _typeFromIntent(intent);
    if (type == VoiceIntentType.unknown) return null;

    final task = data['task']?.toString().trim();
    final summary = data['summary']?.toString().trim();
    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.75;
    if (confidence < 0.45) return null;

    return VoiceIntentResult(
      type: type,
      normalizedText: normalized,
      summary: summary == null || summary.isEmpty
          ? summarizeText(rawText)
          : summary,
      intent: _intentName(type),
      task: task == null || task.isEmpty
          ? _extractTask(rawText, normalized)
          : task,
      time: data['time']?.toString(),
      repeat: data['repeat']?.toString(),
      confidence: confidence.clamp(0.0, 0.99),
      detectedKeywords: _keywords.where(normalized.contains).toList(),
      recommendedPrimaryModel: LightweightNlpModel.gemma2bIt,
      recommendedSecondaryModel: LightweightNlpModel.mobileBertIntent,
      modelUsed: data['model']?.toString(),
      usedGemma: usedGemma,
    );
  }

  VoiceIntentType _typeFromIntent(String intent) {
    switch (intent.toLowerCase()) {
      case 'create_reminder':
      case 'add_reminder':
      case 'hydration_reminder':
        return VoiceIntentType.addReminder;
      case 'call_emergency':
        return VoiceIntentType.callEmergency;
      case 'translate':
        return VoiceIntentType.translate;
      case 'summarize':
        return VoiceIntentType.summarize;
      case 'reminder_list':
        return VoiceIntentType.reminderList;
      case 'daily_schedule':
        return VoiceIntentType.dailySchedule;
      case 'navigation':
        return VoiceIntentType.navigation;
      case 'statistics':
        return VoiceIntentType.statistics;
      case 'internet_query':
        return VoiceIntentType.internet;
      default:
        return VoiceIntentType.unknown;
    }
  }

  VoiceIntentType _detectIntent(String text) {
    if (text.contains('add reminder') ||
        text.contains('remind me') ||
        text.contains('schedule') ||
        text.contains('paalala') ||
        text.contains('paalalahanan') ||
        text.contains('alarm') ||
        text.contains('uminom') ||
        text.contains('gamot')) {
      return VoiceIntentType.addReminder;
    }
    if (text.contains('call') ||
        text.contains('emergency') ||
        text.contains('dial') ||
        text.contains('tawag')) {
      return VoiceIntentType.callEmergency;
    }
    if (text.contains('translate') ||
        text.contains('tagalog') ||
        text.contains('english') ||
        text.contains('isalin')) {
      return VoiceIntentType.translate;
    }
    if (text.contains('summarize') || text.contains('summary')) {
      return VoiceIntentType.summarize;
    }
    if (text.contains('show my reminders') ||
        text.contains('list reminders') ||
        text.contains('mga paalala') ||
        text.contains('next reminder')) {
      return VoiceIntentType.reminderList;
    }
    if (text.contains('today schedule') ||
        text.contains('daily schedule') ||
        text.contains('iskedyul')) {
      return VoiceIntentType.dailySchedule;
    }
    if (text.contains('open settings') ||
        text.contains('open dashboard') ||
        text.contains('buksan')) {
      return VoiceIntentType.navigation;
    }
    if (text.contains('statistics') ||
        text.contains('completion rate') ||
        text.contains('ulat')) {
      return VoiceIntentType.statistics;
    }
    if (text.contains('weather') ||
        text.contains('panahon') ||
        text.contains('what time') ||
        text.contains('anong oras')) {
      return VoiceIntentType.internet;
    }
    return VoiceIntentType.unknown;
  }
}
