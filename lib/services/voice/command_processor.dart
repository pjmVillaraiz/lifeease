import 'package:lifeease/features/voice/application/voice_assistant_service.dart';
import 'package:lifeease/services/voice/reminder_parser.dart';

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
  });

  final VoiceCommandIntent intent;
  final String originalText;
  final String normalizedText;
  final VoiceReminderDraft? reminderDraft;
  final ReminderQueryType? reminderQueryType;
  final VoiceNavigationTarget? navigationTarget;

  bool get isRecognized => intent != VoiceCommandIntent.unknown;
}

class CommandProcessor {
  CommandProcessor({
    VoiceAssistantService? assistant,
    ReminderParser? reminderParser,
  }) : _assistant = assistant ?? const VoiceAssistantService(),
       _reminderParser = reminderParser ?? ReminderParser();

  final VoiceAssistantService _assistant;
  final ReminderParser _reminderParser;

  VoiceCommandResult process(String rawText) {
    final normalized = _normalize(rawText);
    if (normalized.isEmpty) {
      return _unknown(rawText, normalized);
    }

    if (_isCreateReminder(normalized)) {
      final parsed = _reminderParser.parse(_reminderText(rawText));
      final draft = parsed == null
          ? _assistant.parseReminder(_reminderText(rawText))
          : _toVoiceReminderDraft(parsed);
      if (draft != null) {
        return VoiceCommandResult(
          intent: VoiceCommandIntent.createReminder,
          originalText: rawText,
          normalizedText: normalized,
          reminderDraft: draft,
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
      'set reminder',
      'set a reminder',
      'magdagdag ng paalala',
      'paalalahanan',
      'paalala ako',
      'reminder ako',
      'mag remind',
      'mag-remind',
    ]);
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

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
