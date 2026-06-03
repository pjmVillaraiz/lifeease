import 'package:lifeease/features/voice/application/voice_assistant_service.dart';
import 'package:lifeease/features/voice/application/voice_command_processing_module.dart';
import 'package:lifeease/services/translation/google_translation_service.dart';
import 'package:lifeease/services/voice/reminder_parser.dart';
import 'package:lifeease/services/voice/voice_reminder_hints.dart';
import 'package:lifeease/services/voice/voice_time_parser.dart';

typedef VoiceTextTranslator = Future<String> Function(String text);

enum VoiceCommandIntent {
  createReminder,
  reminderList,
  dailySchedule,
  emergency,
  navigation,
  statistics,
  internet,
  unknown,
}

enum VoiceNavigationTarget {
  home,
  reminders,
  settings,
  dashboard,
  voiceAssistant,
}

class VoiceCommandResult {
  const VoiceCommandResult({
    required this.intent,
    required this.originalText,
    required this.normalizedText,
    this.reminderDraft,
    this.reminderQueryType,
    this.navigationTarget,
    this.reminderHasExplicitTime = false,
    this.usedGemma = false,
    this.nlpModelUsed,
    this.nlpSummary,
    this.nlpFailureReason,
  });

  final VoiceCommandIntent intent;
  final String originalText;
  final String normalizedText;
  final VoiceReminderDraft? reminderDraft;
  final ReminderQueryType? reminderQueryType;
  final VoiceNavigationTarget? navigationTarget;
  final bool reminderHasExplicitTime;
  final bool usedGemma;
  final String? nlpModelUsed;
  final String? nlpSummary;
  final String? nlpFailureReason;

  bool get isRecognized => intent != VoiceCommandIntent.unknown;

  String parserBadgeLabel({required bool isTagalog}) {
    if (usedGemma) {
      return isTagalog ? 'Gemma 2 AI' : 'Gemma 2 AI';
    }
    return isTagalog ? 'Lokal na parser' : 'Local rules';
  }

  String? parserDetailLabel({required bool isTagalog}) {
    if (usedGemma) {
      final model = nlpModelUsed?.trim();
      if (model == null || model.isEmpty) {
        return isTagalog ? 'Ginamit ang Gemma 2' : 'Parsed with Gemma 2';
      }
      return isTagalog ? 'Modelo: $model' : 'Model: $model';
    }
    if (nlpModelUsed == 'translation+local-rules') {
      return isTagalog
          ? 'Salin + lokal na patakaran'
          : 'Translation + local rules';
    }
    final failure = nlpFailureReason?.trim();
    if (failure != null && failure.isNotEmpty) {
      return failure;
    }
    return isTagalog
        ? 'Hindi available ang Gemma o hindi nakilala'
        : 'Gemma unavailable or unrecognized';
  }

  VoiceCommandResult withNlpMetadata(VoiceIntentResult nlp) {
    return VoiceCommandResult(
      intent: intent,
      originalText: originalText,
      normalizedText: normalizedText,
      reminderDraft: reminderDraft,
      reminderQueryType: reminderQueryType,
      navigationTarget: navigationTarget,
      reminderHasExplicitTime: reminderHasExplicitTime,
      usedGemma: nlp.usedGemma,
      nlpModelUsed: nlp.modelUsed,
      nlpSummary: nlp.summary,
      nlpFailureReason: nlp.nlpFailureReason,
    );
  }

  VoiceCommandResult withLocalParser({String source = 'local-rules'}) {
    return VoiceCommandResult(
      intent: intent,
      originalText: originalText,
      normalizedText: normalizedText,
      reminderDraft: reminderDraft,
      reminderQueryType: reminderQueryType,
      navigationTarget: navigationTarget,
      reminderHasExplicitTime: reminderHasExplicitTime,
      usedGemma: false,
      nlpModelUsed: source,
      nlpSummary: nlpSummary,
      nlpFailureReason: nlpFailureReason,
    );
  }
}

class CommandProcessor {
  CommandProcessor({
    VoiceAssistantService? assistant,
    ReminderParser? reminderParser,
    GoogleTranslationService? translationService,
    VoiceTextTranslator? translator,
    VoiceCommandProcessingModule? nlpModule,
  }) : _assistant = assistant ?? const VoiceAssistantService(),
       _reminderParser = reminderParser ?? ReminderParser(),
       _translationService = translationService ?? GoogleTranslationService(),
       _translator = translator,
       _nlpModule = nlpModule ?? VoiceCommandProcessingModule();

  final VoiceAssistantService _assistant;
  final ReminderParser _reminderParser;
  final GoogleTranslationService _translationService;
  final VoiceTextTranslator? _translator;
  final VoiceCommandProcessingModule _nlpModule;

  /// Whether Gemma 2 NLP is configured (direct API key or Supabase edge AI).
  bool get isGemmaNlpAvailable => _nlpModule.isGemmaAvailable;

  Future<VoiceCommandResult> processAsync(String rawText) async {
    VoiceIntentResult? lastNlp;

    if (_nlpModule.isGemmaAvailable) {
      try {
        lastNlp = await _nlpModule.parseAsync(rawText);
        final fromGemma = _fromNlpResult(rawText, lastNlp);
        if (fromGemma.isRecognized) return fromGemma;
      } catch (_) {
        // Fall through to rule-based parsing.
      }
    }

    final direct = process(rawText);
    if (direct.isRecognized && !_mayNeedEnglishNormalization(rawText)) {
      return _attachNlpMetadata(direct, lastNlp);
    }

    final translatedText =
        (await (_translator?.call(rawText) ??
                _translationService.translateToEnglish(rawText)))
            .trim();
    if (translatedText.isEmpty ||
        translatedText.toLowerCase() == rawText.trim().toLowerCase()) {
      return _attachNlpMetadata(direct, lastNlp);
    }

    final translated = process(translatedText);
    if (!translated.isRecognized) {
      return _attachNlpMetadata(direct, lastNlp);
    }

    return VoiceCommandResult(
      intent: translated.intent,
      originalText: rawText,
      normalizedText: translated.normalizedText,
      reminderDraft: translated.reminderDraft,
      reminderQueryType: translated.reminderQueryType,
      navigationTarget: translated.navigationTarget,
      reminderHasExplicitTime: translated.reminderHasExplicitTime,
      usedGemma: lastNlp?.usedGemma ?? false,
      nlpModelUsed: lastNlp?.usedGemma == true
          ? lastNlp?.modelUsed
          : 'translation+local-rules',
      nlpSummary: lastNlp?.summary,
      nlpFailureReason: lastNlp?.nlpFailureReason,
    );
  }

  VoiceCommandResult _attachNlpMetadata(
    VoiceCommandResult result,
    VoiceIntentResult? nlp,
  ) {
    if (nlp == null) return result.withLocalParser();
    return result.withNlpMetadata(nlp);
  }

  VoiceCommandResult process(String rawText) {
    final normalized = _normalize(rawText);
    if (normalized.isEmpty) {
      return _unknown(rawText, normalized);
    }

    if (_isCreateReminder(normalized)) {
      final reminderText = _reminderText(rawText);
      final parsed = _reminderParser.parse(reminderText);
      if (parsed != null) {
        return VoiceCommandResult(
          intent: VoiceCommandIntent.createReminder,
          originalText: rawText,
          normalizedText: normalized,
          reminderDraft: _toVoiceReminderDraft(parsed),
          reminderHasExplicitTime: parsed.hasExplicitTime,
        );
      }

      final draft = _assistant.parseReminder(reminderText);
      if (draft != null) {
        return VoiceCommandResult(
          intent: VoiceCommandIntent.createReminder,
          originalText: rawText,
          normalizedText: normalized,
          reminderDraft: draft,
          reminderHasExplicitTime: _hasExplicitTime(_normalize(reminderText)),
        );
      }
    }

    if (_isDailySchedule(normalized)) {
      return VoiceCommandResult(
        intent: VoiceCommandIntent.dailySchedule,
        originalText: rawText,
        normalizedText: normalized,
        reminderQueryType: ReminderQueryType.today,
      );
    }

    final reminderQuery = _reminderQuery(normalized);
    if (reminderQuery != null) {
      return VoiceCommandResult(
        intent: VoiceCommandIntent.reminderList,
        originalText: rawText,
        normalizedText: normalized,
        reminderQueryType: reminderQuery,
        navigationTarget: VoiceNavigationTarget.reminders,
      );
    }

    if (_isEmergency(normalized)) {
      return VoiceCommandResult(
        intent: VoiceCommandIntent.emergency,
        originalText: rawText,
        normalizedText: normalized,
      );
    }

    final navigationTarget = _navigationTarget(normalized);
    if (navigationTarget != null) {
      return VoiceCommandResult(
        intent: VoiceCommandIntent.navigation,
        originalText: rawText,
        normalizedText: normalized,
        navigationTarget: navigationTarget,
      );
    }

    if (_isStatistics(normalized)) {
      return VoiceCommandResult(
        intent: VoiceCommandIntent.statistics,
        originalText: rawText,
        normalizedText: normalized,
      );
    }

    if (_isInternet(normalized)) {
      return VoiceCommandResult(
        intent: VoiceCommandIntent.internet,
        originalText: rawText,
        normalizedText: normalized,
      );
    }

    return _unknown(rawText, normalized);
  }

  String _reminderText(String rawText) {
    final trimmed = rawText.trim();
    final normalized = _normalize(trimmed);
    if (normalized.startsWith('create reminder')) {
      return trimmed.replaceFirst(
        RegExp(r'^\s*create reminder\s*', caseSensitive: false),
        'Add reminder ',
      );
    }
    if (normalized.startsWith('create a reminder')) {
      return trimmed.replaceFirst(
        RegExp(r'^\s*create a reminder\s*', caseSensitive: false),
        'Add reminder ',
      );
    }
    if (normalized.startsWith('make reminder')) {
      return trimmed.replaceFirst(
        RegExp(r'^\s*make reminder\s*', caseSensitive: false),
        'Add reminder ',
      );
    }
    if (normalized.startsWith('make a reminder')) {
      return trimmed.replaceFirst(
        RegExp(r'^\s*make a reminder\s*', caseSensitive: false),
        'Add reminder ',
      );
    }
    if (normalized.startsWith('reminder ako')) {
      return trimmed.replaceFirst(
        RegExp(r'^\s*reminder ako\s*', caseSensitive: false),
        'Add reminder ',
      );
    }
    if (normalized.startsWith('paalala ako')) {
      return trimmed.replaceFirst(
        RegExp(r'^\s*paalala ako\s*', caseSensitive: false),
        'Magdagdag ng paalala ',
      );
    }
    if (normalized.startsWith('mag remind') ||
        normalized.startsWith('mag-remind')) {
      return trimmed.replaceFirst(
        RegExp(r'^\s*mag-?\s*remind\s*', caseSensitive: false),
        'Add reminder ',
      );
    }
    if (_isImplicitReminderAction(normalized) &&
        !_alreadyHasReminderPhrase(normalized)) {
      return 'Add reminder $trimmed';
    }
    return trimmed;
  }

  VoiceReminderDraft _toVoiceReminderDraft(ParsedReminderDraft parsed) {
    return VoiceReminderDraft(
      title: parsed.title,
      note: parsed.note,
      scheduledAt: parsed.scheduledAt,
      repeatType: parsed.repeatType,
      repeatIntervalMinutes: parsed.repeatIntervalMinutes,
      frequencyLabel: parsed.frequencyLabel,
      originalText: parsed.originalText,
    );
  }

  bool _isCreateReminder(String text) {
    return _hasAny(text, const [
          'remind me',
          'add reminder',
          'add a reminder',
          'create reminder',
          'create a reminder',
          'make reminder',
          'make a reminder',
          'set reminder',
          'set a reminder',
          'magdagdag ng paalala',
          'paalalahanan',
          'paalala ako',
          'reminder ako',
          'mag remind',
          'mag-remind',
        ]) ||
        _isImplicitReminderAction(text);
  }

  bool _isImplicitReminderAction(String text) {
    return RegExp(
          r'^\s*(take|drink|use|check|measure|make|book|schedule|eat|have|uminom|inumin|gamitin|kunin)\b',
        ).hasMatch(text) ||
        RegExp(
          r'\b(?:add|create|make|set)\s+(?:a\s+)?\w+\s+reminder\b',
        ).hasMatch(text) ||
        VoiceReminderHints.containsTaskKeyword(text);
  }

  ReminderQueryType? _reminderQuery(String text) {
    if (_hasAny(text, const [
      'show today',
      "show today's reminders",
      'reminders today',
      'reminders ko today',
      'what are my reminders today',
      'mga paalala ngayon',
      'paalala ko ngayon',
      'ipakita ang mga paalala ko ngayon',
      'pakita reminders ko today',
    ])) {
      return ReminderQueryType.today;
    }

    if (_hasAny(text, const [
      'show my reminders',
      'open reminders',
      'list reminders',
      'all reminders',
      'ipakita ang mga paalala ko',
      'pakita reminders ko',
      'mga paalala ko',
    ])) {
      return ReminderQueryType.pendingCount;
    }

    if (_hasAny(text, const [
      'next reminder',
      'susunod na paalala',
      'next na reminder',
    ])) {
      return ReminderQueryType.next;
    }

    return null;
  }

  bool _isDailySchedule(String text) {
    return _hasAny(text, const [
      "read today's schedule",
      'read today schedule',
      'schedule summary',
      'daily summary',
      'today schedule',
      'iskedyul ngayon',
      'basahin ang iskedyul',
      'daily schedule',
    ]);
  }

  bool _isEmergency(String text) {
    return _hasAny(text, const [
      'emergency',
      'call emergency contact',
      'send emergency message',
      'help me',
      'tawag emergency',
      'tumawag ng emergency',
      'kontak emergency',
    ]);
  }

  VoiceNavigationTarget? _navigationTarget(String text) {
    if (_hasAny(text, const ['open settings', 'settings', 'buksan settings'])) {
      return VoiceNavigationTarget.settings;
    }
    if (_hasAny(text, const [
      'open reminders',
      'open reminder',
      'reminders screen',
      'buksan reminders',
      'buksan paalala',
    ])) {
      return VoiceNavigationTarget.reminders;
    }
    if (_hasAny(text, const [
      'open dashboard',
      'dashboard',
      'home screen',
      'open home',
      'buksan dashboard',
    ])) {
      return VoiceNavigationTarget.dashboard;
    }
    if (_hasAny(text, const [
      'open voice assistant',
      'voice assistant',
      'buksan voice assistant',
    ])) {
      return VoiceNavigationTarget.voiceAssistant;
    }
    return null;
  }

  bool _isStatistics(String text) {
    return _hasAny(text, const [
      'show reminder statistics',
      'reminder statistics',
      'completion rate',
      'adherence report',
      'statistics',
      'stats',
      'ulat',
      'completion ko',
    ]);
  }

  bool _isInternet(String text) {
    return _hasAny(text, const [
      'weather',
      'panahon',
      'what time',
      'anong oras',
      'oras ngayon',
      'what day',
      'what date',
      'anong araw',
      'latest news',
      'news today',
      'balita',
      'what is',
      'who is',
      'ano ang',
    ]);
  }

  bool _hasAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }

  VoiceCommandResult _unknown(String rawText, String normalized) {
    return VoiceCommandResult(
      intent: VoiceCommandIntent.unknown,
      originalText: rawText,
      normalizedText: normalized,
    );
  }

  VoiceCommandResult _fromNlpResult(String rawText, VoiceIntentResult nlp) {
    final normalized = nlp.normalizedText;
    final VoiceCommandResult result;
    switch (nlp.type) {
      case VoiceIntentType.addReminder:
        final draft = _reminderDraftFromNlp(rawText, nlp);
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.createReminder,
          originalText: rawText,
          normalizedText: normalized,
          reminderDraft: draft,
          reminderHasExplicitTime:
              draft != null &&
              (nlp.time != null ||
                  VoiceTimeParser.hasExplicitTime(rawText) ||
                  VoiceTimeParser.hasExplicitTime(nlp.task)),
        );
      case VoiceIntentType.callEmergency:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.emergency,
          originalText: rawText,
          normalizedText: normalized,
        );
      case VoiceIntentType.translate:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.internet,
          originalText: rawText,
          normalizedText: normalized,
        );
      case VoiceIntentType.summarize:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.dailySchedule,
          originalText: rawText,
          normalizedText: normalized,
          reminderQueryType: ReminderQueryType.today,
        );
      case VoiceIntentType.reminderList:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.reminderList,
          originalText: rawText,
          normalizedText: normalized,
          reminderQueryType: _reminderQueryFromNlp(normalized),
          navigationTarget: VoiceNavigationTarget.reminders,
        );
      case VoiceIntentType.dailySchedule:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.dailySchedule,
          originalText: rawText,
          normalizedText: normalized,
          reminderQueryType: ReminderQueryType.today,
        );
      case VoiceIntentType.navigation:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.navigation,
          originalText: rawText,
          normalizedText: normalized,
          navigationTarget: _navigationFromNlp(normalized),
        );
      case VoiceIntentType.statistics:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.statistics,
          originalText: rawText,
          normalizedText: normalized,
        );
      case VoiceIntentType.internet:
        result = VoiceCommandResult(
          intent: VoiceCommandIntent.internet,
          originalText: rawText,
          normalizedText: normalized,
        );
      case VoiceIntentType.unknown:
        return _unknown(rawText, normalized).withNlpMetadata(nlp);
    }
    return result.withNlpMetadata(nlp);
  }

  VoiceReminderDraft? _reminderDraftFromNlp(
    String rawText,
    VoiceIntentResult nlp,
  ) {
    final synthetic = _buildSyntheticReminderText(rawText, nlp);
    final parsed = _reminderParser.parse(synthetic);
    if (parsed != null) return _toVoiceReminderDraft(parsed);

    final assistantDraft = _assistant.parseReminder(synthetic);
    if (assistantDraft != null) return assistantDraft;

    if (nlp.task.trim().isEmpty) return null;

    final now = DateTime.now();
    final scheduledAt = now.add(const Duration(hours: 1));
    final repeat = _repeatFromNlp(nlp.repeat);
    return VoiceReminderDraft(
      title: nlp.task.trim(),
      note: nlp.summary.trim(),
      scheduledAt: scheduledAt,
      repeatType: repeat.repeatType,
      repeatIntervalMinutes: repeat.repeatIntervalMinutes,
      frequencyLabel: repeat.label,
      originalText: rawText,
    );
  }

  String _buildSyntheticReminderText(String rawText, VoiceIntentResult nlp) {
    final parts = <String>[
      'Add reminder',
      nlp.task.trim(),
      if (nlp.time != null) 'at ${nlp.time}',
      if (nlp.repeat != null) nlp.repeat!,
    ];
    if (parts.length <= 2 && rawText.trim().isNotEmpty) {
      return 'Add reminder ${rawText.trim()}';
    }
    return parts.join(' ');
  }

  ({String repeatType, int repeatIntervalMinutes, String label})
  _repeatFromNlp(String? repeat) {
    switch (repeat?.toLowerCase()) {
      case 'daily':
        return (repeatType: 'daily', repeatIntervalMinutes: 1440, label: 'Daily');
      case 'weekly':
        return (
          repeatType: 'weekly',
          repeatIntervalMinutes: 10080,
          label: 'Weekly',
        );
      case 'monthly':
        return (
          repeatType: 'monthly',
          repeatIntervalMinutes: 43200,
          label: 'Monthly',
        );
      default:
        return (repeatType: 'none', repeatIntervalMinutes: 0, label: 'Once');
    }
  }

  ReminderQueryType _reminderQueryFromNlp(String text) {
    if (_hasAny(text, const [
      'today',
      'ngayon',
      'next reminder',
      'susunod',
    ])) {
      return text.contains('next') || text.contains('susunod')
          ? ReminderQueryType.next
          : ReminderQueryType.today;
    }
    return ReminderQueryType.pendingCount;
  }

  VoiceNavigationTarget? _navigationFromNlp(String text) {
    if (_hasAny(text, const ['settings', 'setting'])) {
      return VoiceNavigationTarget.settings;
    }
    if (_hasAny(text, const ['reminder', 'paalala'])) {
      return VoiceNavigationTarget.reminders;
    }
    if (_hasAny(text, const ['dashboard', 'home'])) {
      return VoiceNavigationTarget.dashboard;
    }
    if (_hasAny(text, const ['voice assistant', 'assistant'])) {
      return VoiceNavigationTarget.voiceAssistant;
    }
    return VoiceNavigationTarget.dashboard;
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _mayNeedEnglishNormalization(String rawText) {
    final text = _normalize(rawText);
    return _hasAny(text, const [
      'paalala',
      'paalalahanan',
      'gamot',
      'uminom',
      'bukas',
      'ngayon',
      'araw-araw',
      'kada',
      'oras',
      'umaga',
      'gabi',
      'tawag',
      'tumawag',
    ]);
  }

  bool _hasExplicitTime(String text) => VoiceTimeParser.hasExplicitTime(text);

  bool _alreadyHasReminderPhrase(String text) {
    return _hasAny(text, const [
      'remind me',
      'add reminder',
      'add a reminder',
      'create reminder',
      'create a reminder',
      'make reminder',
      'make a reminder',
      'set reminder',
      'set a reminder',
      'paalalahanan',
      'magdagdag ng paalala',
    ]) ||
        RegExp(
          r'\b(?:add|create|make|set)\s+(?:a\s+)?\w+\s+reminder\b',
        ).hasMatch(text);
  }
}
