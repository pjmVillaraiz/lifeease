import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/shared/providers/language_controller.dart';
import 'package:lifeease/shared/widgets/app_navigation.dart';
import 'package:lifeease/shared/widgets/emergency_fab_widget.dart';
import 'package:lifeease/shared/widgets/empty_state_widget.dart';
import 'package:lifeease/shared/widgets/loading_skeleton_widget.dart';

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/backend/supabase_auth_service.dart';
import 'package:lifeease/core/services/backend/user_profile_service.dart';
import 'package:lifeease/core/services/emergency/emergency_route_processing_module.dart';
import 'package:lifeease/core/services/notifications/reminder_notification_service.dart';
import 'package:lifeease/features/reminders/application/due_reminder_prompt_coordinator.dart';
import 'package:lifeease/features/reminders/application/location_reminder_service.dart';
import 'package:lifeease/features/reminders/application/reminder_insights_service.dart';
import 'package:lifeease/features/reminders/models/reminder_model.dart';
import 'package:lifeease/features/reminders/presentation/add_reminder_screen/add_reminder_screen.dart';
import 'package:lifeease/features/sus_evaluation/application/sus_processing_module.dart';
import 'package:lifeease/features/translation/application/language_translation_processing_module.dart';
import 'package:lifeease/features/voice/application/speech_processing_module.dart';
import 'package:lifeease/features/voice/application/voice_assistant_service.dart';
import 'package:lifeease/services/voice/command_processor.dart';
import 'package:lifeease/services/voice/voice_reminder_hints.dart';
import 'package:lifeease/services/voice/voice_time_parser.dart';

import './widgets/reminder_card_widget.dart';

class _GuidedFrequency {
  const _GuidedFrequency(
    this.repeatType,
    this.repeatIntervalMinutes,
    this.label,
  );

  final String repeatType;
  final int repeatIntervalMinutes;
  final String label;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const bool _enableVoiceCommandParsing = true;

  int _currentNavIndex = 0;
  bool _isLoading = true;
  List<ReminderModel> _reminders = [];
  bool _isListening = false;
  bool _isProcessingVoice = false;
  bool _isGuidedListening = false;
  bool _voiceListenCancelled = false;
  String _liveTranscript = '';
  String _voiceStatus = '';
  bool _voiceUsedGemma = false;
  String? _voiceParserLabel;
  String? _voiceParserDetail;
  String? _firstName;

  late final ReminderRepository _reminderRepository;
  late final SupabaseAuthService _authService;
  late final UserProfileService _profileService;
  late final SpeechProcessingModule _speechModule;
  late final VoiceAssistantService _assistantService;
  late final CommandProcessor _commandProcessor;
  late final ReminderInsightsService _insightsService;
  late final LanguageTranslationProcessingModule _translationProcessor;
  late final EmergencyRouteProcessingModule _emergencyRouteProcessor;
  late final SusProcessingModule _susProcessor;
  late final StreamSubscription<void> _reminderChanges;
  StreamSubscription<double>? _voiceAmplitudeSubscription;
  Timer? _statusRefreshTimer;
  Timer? _noVoiceDetectedTimer;
  Timer? _voiceAutoStopTimer;
  bool _voiceDetectedDuringRecording = false;
  bool _isReconcilingDueReminders = false;
  bool _hasScheduledLoadedReminders = false;
  late AnimationController _listEntranceController;

  static const List<EmergencyContact> _emergencyContacts = [
    EmergencyContact(
      id: 1,
      name: 'Caregiver',
      phone: '112',
      relationship: 'Primary',
      priority: 1,
    ),
  ];

  String tr(bool isTagalog, String en, String tl) {
    return isTagalog ? tl : en;
  }

  @override
  void initState() {
    super.initState();
    _listEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _reminderRepository = ReminderRepository();
    _authService = SupabaseAuthService();
    _profileService = UserProfileService();
    _speechModule = SpeechProcessingModule();
    _assistantService = const VoiceAssistantService();
    _commandProcessor = CommandProcessor(assistant: _assistantService);
    _insightsService = const ReminderInsightsService();
    _translationProcessor = LanguageTranslationProcessingModule();
    _emergencyRouteProcessor = EmergencyRouteProcessingModule();
    _susProcessor = SusProcessingModule();
    WidgetsBinding.instance.addObserver(this);
    _reminderChanges = ReminderRepository.changes.listen((_) {
      _loadReminders(showLoading: false);
    });
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      _reconcileDueReminders();
    });
    LocationReminderService.instance.start();
    _loadReminders();
    _loadProfileName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderChanges.cancel();
    _stopVoiceRecordingWatchdog();
    _statusRefreshTimer?.cancel();
    unawaited(_speechModule.cancelListening());
    LocationReminderService.instance.stop();
    _listEntranceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadReminders(showLoading: false);
      _loadProfileName();
      LocationReminderService.instance.start();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_speechModule.cancelListening());
      if (mounted && (_isListening || _isProcessingVoice || _isGuidedListening)) {
        _voiceListenCancelled = true;
        _resetVoiceIdleState();
      }
    }
  }

  Future<void> _loadProfileName() async {
    if (_authService.currentUser == null) {
      if (!mounted) return;
      setState(() => _firstName = null);
      return;
    }

    final profile = await _profileService.loadProfile();
    if (!mounted) return;
    setState(() => _firstName = profile.resolvedFirstName);
  }

  Future<void> _loadReminders({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading && !_isLoading) {
      setState(() => _isLoading = true);
    }

    var rows = await _reminderRepository.loadReminders();
    if (!_hasScheduledLoadedReminders) {
      _hasScheduledLoadedReminders = true;
      unawaited(
        ReminderNotificationService.instance.schedulePendingReminders(rows),
      );
    } else {
      final changed = await ReminderNotificationService.instance
          .reconcileDueReminders(rows);
      if (changed) {
        rows = await _reminderRepository.loadReminders();
      }
    }
    if (!mounted) return;

    final loaded = rows.map(ReminderModel.fromMap).toList();
    loaded.sort(
      (a, b) => a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis),
    );

    setState(() {
      _reminders = loaded;
      _isLoading = false;
    });

    _listEntranceController.forward(from: 0.0);
    unawaited(
      DueReminderPromptCoordinator.instance.showRecentlyDueReminderPrompts(
        loaded,
      ),
    );
  }

  Future<void> _reconcileDueReminders() async {
    if (_isReconcilingDueReminders) return;
    _isReconcilingDueReminders = true;
    try {
      final rows = _reminders.map((reminder) => reminder.toMap()).toList();
      final changed = await ReminderNotificationService.instance
          .reconcileDueReminders(rows);
      if (changed && mounted) {
        await _loadReminders(showLoading: false);
      }
    } finally {
      _isReconcilingDueReminders = false;
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _loadReminders();
  }

  Future<void> _deleteReminder(ReminderModel reminder) async {
    setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
    await _reminderRepository.deleteReminder(reminder.id);
    await ReminderNotificationService.instance.cancelReminder(reminder.id);
  }

  Future<void> _markComplete(ReminderModel reminder) async {
    await _reminderRepository.markReminderComplete(reminder.toMap());
    if (reminder.isRepeating) {
      final updated = await _reminderRepository.loadReminderById(reminder.id);
      if (updated != null) {
        await ReminderNotificationService.instance.scheduleReminder(updated);
      }
      await _loadReminders(showLoading: false);
    } else {
      setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
      await ReminderNotificationService.instance.cancelReminder(reminder.id);
    }
    HapticFeedback.mediumImpact();
  }

  Future<void> _editReminder(ReminderModel reminder) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddReminderScreen(editReminder: reminder.toMap()),
      ),
    );

    if (updated == true) {
      await _loadReminders();
    }
  }

  Future<void> _onVoiceButtonTap() async {
    if (_isGuidedListening || (_isProcessingVoice && !_isListening)) {
      await _abortActiveVoiceSession();
    }

    if (_isListening) {
      await _stopVoiceRecordingAndTranscribe();
      return;
    }

    if (_isProcessingVoice) {
      await _abortActiveVoiceSession();
    }

    await _onSpeakCommand();
  }

  Future<void> _abortActiveVoiceSession() async {
    _voiceListenCancelled = true;
    _stopVoiceRecordingWatchdog();
    await _speechModule.cancelListening();
    _resetVoiceIdleState();
  }

  void _resetVoiceIdleState() {
    if (!mounted) return;
    setState(() {
      _liveTranscript = '';
      _isListening = false;
      _isProcessingVoice = false;
      _isGuidedListening = false;
      _voiceStatus = '';
      _voiceListenCancelled = false;
    });
  }

  void _clearVoiceParserResult() {
    if (!mounted) return;
    setState(() {
      _voiceUsedGemma = false;
      _voiceParserLabel = null;
      _voiceParserDetail = null;
    });
  }

  void _applyVoiceParserResult(VoiceCommandResult result) {
    if (!mounted) return;
    final isTagalog = LanguageController.isTagalog.value;
    setState(() {
      _voiceUsedGemma = result.usedGemma;
      _voiceParserLabel = result.parserBadgeLabel(isTagalog: isTagalog);
      _voiceParserDetail =
          result.usedGemma &&
              result.nlpSummary?.trim().isNotEmpty == true
          ? result.nlpSummary!.trim()
          : result.parserDetailLabel(isTagalog: isTagalog);
    });
  }

  Future<void> _showUnrecognizedCommandHelp() async {
    final isTagalog = LanguageController.isTagalog.value;
    final message = tr(
      isTagalog,
      'I did not understand that. Tap the microphone to try a voice reminder, or tap + Add Reminder to create one manually.',
      'Hindi ko naintindihan iyon. I-tap ang microphone para subukan ang voice reminder, o i-tap ang + Magdagdag ng Paalala para gumawa nang manual.',
    );
    _resetVoiceIdleState();
    _showSnack(message);
    try {
      await _speechModule.speak(message);
    } catch (_) {
      // Snackbar is enough when TTS is unavailable.
    }
  }

  Future<void> _onSpeakCommand() async {
    if (_isProcessingVoice) return;

    HapticFeedback.heavyImpact();
    _clearVoiceParserResult();
    final isTagalog = LanguageController.isTagalog.value;
    setState(() {
      _isListening = false;
      _isProcessingVoice = true;
      _voiceListenCancelled = false;
      _liveTranscript = '';
      _voiceStatus = tr(isTagalog, "I'm listening.", 'Nakikinig ako.');
    });
    try {
      await _speechModule.speak(
        tr(isTagalog, "I'm listening.", 'Nakikinig ako.'),
      );
      if (!mounted || _voiceListenCancelled) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _isProcessingVoice = false;
            _voiceListenCancelled = false;
            _voiceStatus = '';
          });
        }
        return;
      }
      setState(() {
        _isListening = true;
        _isProcessingVoice = false;
        _voiceStatus = tr(isTagalog, 'Recording...', 'Nagre-record...');
      });
      await _speechModule.startGroqRecording();
      _startVoiceRecordingWatchdog();
    } catch (error) {
      if (!mounted) return;
      _resetVoiceIdleState();
      await _reportVoiceError(error);
    }
  }

  Future<void> _stopVoiceRecordingAndTranscribe() async {
    if (!_isListening) return;

    HapticFeedback.mediumImpact();
    _stopVoiceRecordingWatchdog();
    setState(() {
      _isListening = false;
      _isProcessingVoice = true;
      _voiceStatus = tr(
        LanguageController.isTagalog.value,
        'Uploading...',
        'Ina-upload...',
      );
    });

    try {
      final transcript = await _speechModule.stopGroqRecordingAndTranscribe(
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _voiceStatus = status == 'Transcribing...'
                ? tr(
                    LanguageController.isTagalog.value,
                    'Transcribing...',
                    'Isinasalin sa text...',
                  )
                : tr(
                    LanguageController.isTagalog.value,
                    'Uploading...',
                    'Ina-upload...',
                  );
          });
        },
      );
      if (!mounted) return;

      setState(() {
        _isProcessingVoice = false;
        _voiceListenCancelled = false;
        _voiceStatus = '';
        _liveTranscript = transcript ?? '';
      });
      if (!_voiceListenCancelled &&
          _enableVoiceCommandParsing &&
          transcript != null &&
          transcript.trim().isNotEmpty) {
        await _handleCommandText(transcript);
      }
      if (_voiceListenCancelled && mounted) {
        setState(() => _voiceListenCancelled = false);
      }
    } catch (error) {
      if (!mounted) return;
      _resetVoiceIdleState();
      await _reportVoiceError(error);
    }
  }

  void _startVoiceRecordingWatchdog() {
    _stopVoiceRecordingWatchdog();
    _voiceDetectedDuringRecording = false;
    _voiceAmplitudeSubscription = _speechModule.groqAmplitudeDb().listen(
      (currentDb) {
        if (currentDb > -45) {
          _voiceDetectedDuringRecording = true;
          _voiceAutoStopTimer?.cancel();
          _voiceAutoStopTimer = null;
        } else if (_voiceDetectedDuringRecording && _voiceAutoStopTimer == null) {
          _voiceAutoStopTimer = Timer(const Duration(seconds: 2), () {
            if (!mounted || !_isListening || !_voiceDetectedDuringRecording) {
              return;
            }
            unawaited(_stopVoiceRecordingAndTranscribe());
          });
        }
      },
    );
    _noVoiceDetectedTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted || !_isListening || _voiceDetectedDuringRecording) return;
      unawaited(_handleNoVoiceDetected());
    });
  }

  void _stopVoiceRecordingWatchdog() {
    _noVoiceDetectedTimer?.cancel();
    _noVoiceDetectedTimer = null;
    _voiceAutoStopTimer?.cancel();
    _voiceAutoStopTimer = null;
    unawaited(_voiceAmplitudeSubscription?.cancel());
    _voiceAmplitudeSubscription = null;
  }

  Future<void> _handleNoVoiceDetected() async {
    _voiceListenCancelled = true;
    _stopVoiceRecordingWatchdog();
    await _speechModule.cancelListening();
    if (!mounted) return;
    _resetVoiceIdleState();
    await _respondFromAssistant(
      tr(
        LanguageController.isTagalog.value,
        'I did not hear anything. Tap the microphone to try again, or tap + Add Reminder.',
        'Wala akong narinig. I-tap muli ang microphone, o i-tap ang + Magdagdag ng Paalala.',
      ),
    );
  }

  Future<void> _handleCommandText(String input) async {
    if (_isReminderCreationWakePhrase(input)) {
      await _listenForReminderDetails();
      return;
    }

    VoiceCommandResult result;
    try {
      result = await _commandProcessor.processAsync(input);
    } catch (_) {
      result = _commandProcessor.process(input);
    }
    if (!mounted) return;

    _applyVoiceParserResult(result);

    switch (result.intent) {
      case VoiceCommandIntent.createReminder:
        final draft = result.reminderDraft;
        if (draft == null) break;
        if (!result.reminderHasExplicitTime) {
          await _askForMissingReminderTime(result.originalText);
          return;
        }
        await _confirmVoiceReminder(draft);
        return;
      case VoiceCommandIntent.reminderList:
        unawaited(
          Navigator.pushNamed(context, AppRoutes.allRemindersScreen).then((_) {
            if (!mounted) return;
            _loadReminders(showLoading: false);
          }),
        );
        await _answerReminderQuery(
          result.reminderQueryType ?? ReminderQueryType.pendingCount,
        );
        _resetVoiceIdleState();
        return;
      case VoiceCommandIntent.dailySchedule:
        await _readTodaySchedule();
        _resetVoiceIdleState();
        return;
      case VoiceCommandIntent.emergency:
        await _openEmergencyAction();
        _resetVoiceIdleState();
        return;
      case VoiceCommandIntent.navigation:
        _navigateFromVoice(result.navigationTarget);
        _resetVoiceIdleState();
        return;
      case VoiceCommandIntent.statistics:
        await _showStatisticsSummary();
        _resetVoiceIdleState();
        return;
      case VoiceCommandIntent.internet:
        await _respondFromAssistant(
          await _assistantService.answerOnline(input),
        );
        _resetVoiceIdleState();
        return;
      case VoiceCommandIntent.unknown:
        break;
    }

    if (_mayBeReminderMissingDetails(input)) {
      await _askForMissingReminderTime(input);
      return;
    }

    await _showUnrecognizedCommandHelp();
  }

  Future<void> _askForMissingReminderTime(String input) async {
    final isTagalog = LanguageController.isTagalog.value;
    for (var attempt = 0; attempt < 3; attempt++) {
      final answer = await _listenForGuidedReminderAnswer(
        tr(
          isTagalog,
          'What time should I remind you?',
          'Anong oras kita paaalalahanan?',
        ),
      );
      if (_voiceListenCancelled) {
        _resetVoiceIdleState();
        return;
      }
      if (answer == null || answer.trim().isEmpty) continue;

      // Try to extract time directly from answer first
      final extractedTime = _timeFromGuidedSpeech(answer);
      if (extractedTime != null) {
        // Convert 24-hour format to 12-hour format with AM/PM
        var displayHour = extractedTime.hour;
        var ampm = 'AM';
        
        if (displayHour == 0) {
          displayHour = 12; // Midnight
          ampm = 'AM';
        } else if (displayHour < 12) {
          ampm = 'AM';
        } else if (displayHour == 12) {
          ampm = 'PM'; // Noon
        } else {
          displayHour = displayHour - 12; // Afternoon/Evening
          ampm = 'PM';
        }
        
        final timeStr = '$displayHour:${extractedTime.minute.toString().padLeft(2, '0')} $ampm';
        final completedText = '$input at $timeStr';
        final completed = _commandProcessor.process(completedText);
        final draft = completed.reminderDraft;
        if (completed.intent == VoiceCommandIntent.createReminder &&
            draft != null &&
            completed.reminderHasExplicitTime) {
          await _confirmVoiceReminder(draft);
          return;
        }
      }

      // Fallback: try the original way with the answer as-is
      // This should handle natural sentence variations
      final completedText = '$input at $answer';
      final completed = _commandProcessor.process(completedText);
      final draft = completed.reminderDraft;
      if (completed.intent == VoiceCommandIntent.createReminder &&
          draft != null &&
          completed.reminderHasExplicitTime) {
        await _confirmVoiceReminder(draft);
        return;
      }

      await _respondFromAssistant(
        tr(
          isTagalog,
          'I could not understand the time. Please say it like 10 PM.',
          'Hindi ko naintindihan ang oras. Sabihin tulad ng 10 PM.',
        ),
      );
    }

    await _guidedReminderFailed();
  }

  bool _mayBeReminderMissingDetails(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('reminder') ||
        normalized.contains('paalala') ||
        RegExp(
          r'^\s*(take|drink|use|check|measure|make|book|schedule|uminom|inumin|gamitin|kunin)\b',
        ).hasMatch(normalized) ||
        _containsAny(normalized, const [
          'pill',
          'pills',
          'medicine',
          'medication',
          'meds',
          'vitamin',
          'vitamins',
          'gamot',
          'tableta',
          'appointment',
          'checkup',
          'check-up',
          'food',
          'lunch',
          'dinner',
          'breakfast',
          'brunch',
          'snack',
          'meal',
          'meals',
          'grocery',
          'groceries',
          'hospital',
          'dentist',
        ]);
  }

  Future<void> _openEmergencyAction() async {
    final phone = _emergencyContacts.first.phone;
    final launched = await _emergencyRouteProcessor.call(phone);
    if (!mounted) return;
    _showSnack(
      launched
          ? tr(
              LanguageController.isTagalog.value,
              'Opening emergency dialer...',
              'Binubuksan ang emergency dialer...',
            )
          : tr(
              LanguageController.isTagalog.value,
              'Unable to open emergency dialer.',
              'Hindi mabuksan ang emergency dialer.',
            ),
    );
  }

  void _navigateFromVoice(VoiceNavigationTarget? target) {
    if (!mounted || target == null) return;
    switch (target) {
      case VoiceNavigationTarget.home:
      case VoiceNavigationTarget.dashboard:
        _showSnack(
          tr(
            LanguageController.isTagalog.value,
            'Dashboard is already open.',
            'Bukas na ang dashboard.',
          ),
        );
      case VoiceNavigationTarget.reminders:
        Navigator.pushNamed(context, AppRoutes.allRemindersScreen).then((_) {
          if (!mounted) return;
          _loadReminders(showLoading: false);
        });
      case VoiceNavigationTarget.settings:
        Navigator.pushNamed(context, AppRoutes.settingsScreen);
      case VoiceNavigationTarget.voiceAssistant:
        _showSnack(
          tr(
            LanguageController.isTagalog.value,
            'Voice assistant is ready.',
            'Handa na ang voice assistant.',
          ),
        );
    }
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    setState(() => _currentNavIndex = index);

    // Bottom Navigation Map
    // 0: Home
    // 1: Reminders
    // 2: Voice
    // 3: Translate
    // 4: Settings
    if (index == 1) {
      Navigator.pushNamed(context, AppRoutes.allRemindersScreen).then((_) {
        setState(() => _currentNavIndex = 0);
        _loadReminders();
      });
    } else if (index == 2) {
      unawaited(_onVoiceButtonTap());
      setState(() => _currentNavIndex = 0);
    } else if (index == 3) {
      _showTranslationDialog('');
      setState(() => _currentNavIndex = 0);
    } else if (index == 4) {
      Navigator.pushNamed(context, AppRoutes.settingsScreen).then((_) {
        setState(() => _currentNavIndex = 0);
      });
    }
  }

  Future<void> _readTodaySchedule() async {
    await _respondFromAssistant(_insightsService.spokenSchedule(_reminders));
  }

  Future<void> _showStatisticsSummary() async {
    final isTagalog = LanguageController.isTagalog.value;
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = _reminders
        .where(
          (r) =>
              !r.isCompleted &&
              !r.isCompletedToday &&
              !r.isCanceled &&
              !r.isSkippedToday &&
              !r.isMissedToday &&
              r.scheduledTimeMillis >= now,
        )
        .length;
    final completed = _reminders.where((r) => r.isCompletedToday).length;
    final missed = _reminders
        .where(
          (r) =>
              r.isMissedToday ||
              (!r.isCompleted && !r.isCanceled && r.scheduledTimeMillis < now),
        )
        .length;
    final total = pending + completed + missed;
    final completionRate = total == 0 ? 0 : ((completed / total) * 100).round();

    await _respondFromAssistant(
      tr(
        isTagalog,
        'Today you have $pending pending reminders, $completed completed reminders, and $missed missed reminders. Your completion rate is $completionRate percent.',
        'Ngayon, mayroon kang $pending na pending na paalala, $completed na natapos, at $missed na nalagpasan. Ang completion rate mo ay $completionRate percent.',
      ),
    );
  }

  bool _isReminderCreationWakePhrase(String input) {
    final normalized = input.trim().toLowerCase();
    return normalized == 'add reminder' ||
        normalized == 'add a reminder' ||
        normalized == 'paalala' ||
        normalized == 'magdagdag ng paalala';
  }

  Future<void> _listenForReminderDetails() async {
    final isTagalog = LanguageController.isTagalog.value;
    final title = await _listenForGuidedReminderAnswer(
      tr(
        isTagalog,
        'What would you like me to remind you about?',
        'Ano ang gusto mong ipaalala ko?',
      ),
    );
    if (title == null || title.trim().isEmpty) {
      await _guidedReminderFailed();
      return;
    }

    String note = '';
    final noteCommand = await _listenForGuidedReminderAnswer(
      tr(
        isTagalog,
        'Say Note to add a note, or say Set Time to continue.',
        'Sabihin ang Tala para magdagdag ng tala, o Itakda ang Oras para magpatuloy.',
      ),
    );
    if (_isNoteKeyword(noteCommand ?? '')) {
      note =
          await _listenForGuidedReminderAnswer(
            tr(isTagalog, 'Please tell me the note.', 'Pakisabi ang tala.'),
          ) ??
          '';
    }

    final timeText = await _collectGuidedReminderTime(noteCommand);
    if (timeText == null || timeText.trim().isEmpty) {
      await _guidedReminderFailed();
      return;
    }
    final time = _timeFromGuidedSpeech(timeText);
    if (time == null) {
      await _respondFromAssistant(
        tr(
          isTagalog,
          'I could not understand the time. Tap the microphone to try again, or tap + Add Reminder.',
          'Hindi ko naintindihan ang oras. I-tap muli ang microphone, o i-tap ang + Magdagdag ng Paalala.',
        ),
      );
      _resetVoiceIdleState();
      return;
    }

    final frequencyCommand = await _listenForGuidedReminderAnswer(
      tr(
        isTagalog,
        'Say Frequency to continue.',
        'Sabihin ang Dalas para magpatuloy.',
      ),
    );
    if (frequencyCommand == null || frequencyCommand.trim().isEmpty) {
      await _guidedReminderFailed();
      return;
    }

    var frequencyText = frequencyCommand;
    if (_isFrequencyKeyword(frequencyCommand)) {
      frequencyText =
          await _listenForGuidedReminderAnswer(
            tr(
              isTagalog,
              'How often should LifeEase remind you?',
              'Gaano kadalas ka dapat paalalahanan ng LifeEase?',
            ),
          ) ??
          '';
    }
    if (frequencyText.trim().isEmpty) {
      await _guidedReminderFailed();
      return;
    }

    var frequency = _frequencyFromGuidedSpeech(frequencyText);
    if (_isCustomKeyword(frequencyText)) {
      final customText =
          await _listenForGuidedReminderAnswer(
            tr(
              isTagalog,
              'Choose your custom interval.',
              'Pumili ng custom na pagitan ng oras.',
            ),
          ) ??
          '';
      if (customText.trim().isEmpty) {
        await _guidedReminderFailed();
        return;
      }
      frequencyText = customText;
      frequency = _frequencyFromGuidedSpeech(customText);
    }

    final now = DateTime.now();
    var scheduledAt = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduledAt.isAfter(now)) {
      scheduledAt = scheduledAt.add(const Duration(days: 1));
    }

    final draft = VoiceReminderDraft(
      title: _capitalizeGuidedTitle(title),
      note: note.trim(),
      scheduledAt: scheduledAt,
      repeatType: frequency.repeatType,
      repeatIntervalMinutes: frequency.repeatIntervalMinutes,
      frequencyLabel: frequency.label,
      originalText:
          'Guided reminder: title=$title note=$note time=$timeText frequency=$frequencyText',
    );

    await _speakGuidedReminderSummary(draft);
    await _confirmVoiceReminder(draft);
  }

  Future<String?> _collectGuidedReminderTime(String? previousAnswer) async {
    if (_timeFromGuidedSpeech(previousAnswer ?? '') != null) {
      return previousAnswer;
    }
    final isTagalog = LanguageController.isTagalog.value;
    if (_isSetTimeKeyword(previousAnswer ?? '')) {
      return _listenForGuidedReminderAnswer(
        tr(
          isTagalog,
          'What time should I remind you?',
          'Anong oras kita paaalalahanan?',
        ),
      );
    }

    final setTimeCommand = await _listenForGuidedReminderAnswer(
      tr(
        isTagalog,
        'Say Set Time to continue.',
        'Sabihin ang Itakda ang Oras para magpatuloy.',
      ),
    );
    if (_timeFromGuidedSpeech(setTimeCommand ?? '') != null) {
      return setTimeCommand;
    }
    if (_isSetTimeKeyword(setTimeCommand ?? '')) {
      return _listenForGuidedReminderAnswer(
        tr(
          isTagalog,
          'What time should I remind you?',
          'Anong oras kita paaalalahanan?',
        ),
      );
    }
    return _listenForGuidedReminderAnswer(
      tr(
        isTagalog,
        'What time should I remind you?',
        'Anong oras kita paaalalahanan?',
      ),
    );
  }

  Future<String?> _listenForGuidedReminderAnswer(String prompt) async {
    await _speechModule.speak(prompt);
    if (!mounted) return null;
    setState(() {
      _isGuidedListening = true;
      _isListening = true;
      _isProcessingVoice = false;
      _voiceStatus = tr(
        LanguageController.isTagalog.value,
        'Listening...',
        'Nakikinig...',
      );
      _liveTranscript = '';
    });

    final answer = await _speechModule.listenOnce(
      listenFor: const Duration(seconds: 8),
      onLiveText: (text) {
        if (!mounted) return;
        setState(() => _liveTranscript = text);
      },
    );
    final cleanAnswer = _removePromptEcho(answer?.trim(), prompt);

    if (!mounted) return cleanAnswer;
    setState(() {
      _isGuidedListening = false;
      _isListening = false;
      _isProcessingVoice = false;
      _voiceStatus = '';
      _liveTranscript = cleanAnswer ?? _liveTranscript;
    });
    return cleanAnswer;
  }

  String? _removePromptEcho(String? answer, String prompt) {
    final trimmed = answer?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final normalizedAnswer = _normalizeVoiceEchoText(trimmed);
    final normalizedPrompt = _normalizeVoiceEchoText(prompt);
    if (normalizedPrompt.isEmpty ||
        !normalizedAnswer.contains(normalizedPrompt)) {
      return trimmed;
    }

    final promptWords = normalizedPrompt.split(' ');
    final answerWords = trimmed.split(RegExp(r'\s+'));
    final normalizedWords = answerWords.map(_normalizeVoiceEchoText).toList();
    for (var i = 0; i <= normalizedWords.length - promptWords.length; i++) {
      final candidate = normalizedWords
          .skip(i)
          .take(promptWords.length)
          .join(' ');
      if (candidate == normalizedPrompt) {
        final remaining = <String>[
          ...answerWords.take(i),
          ...answerWords.skip(i + promptWords.length),
        ].join(' ').trim();
        return remaining.isEmpty ? null : remaining;
      }
    }

    return null;
  }

  String _normalizeVoiceEchoText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _guidedReminderFailed() async {
    if (_voiceListenCancelled) return;

    _resetVoiceIdleState();

    await _respondFromAssistant(
      tr(
        LanguageController.isTagalog.value,
        'I did not hear the reminder details. Tap the microphone to try again, or tap + Add Reminder.',
        'Hindi ko narinig ang detalye ng paalala. I-tap muli ang microphone, o i-tap ang + Magdagdag ng Paalala.',
      ),
    );
  }

  TimeOfDay? _timeFromGuidedSpeech(String value) {
    if (value.isEmpty) return null;
    final normalized = _normalizeSpokenNumbers(value.trim().toLowerCase());
    final parsed = VoiceTimeParser.parse(normalized);
    if (parsed == null) return null;
    return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
  }

  String _normalizeSpokenNumbers(String text) {
    var result = text;
    
    // Map of spoken numbers to digits - sorted by length (longest first) to avoid conflicts
    const numberMap = {
      'twenty-three': '23', 'twenty-two': '22', 'twenty-one': '21',
      'twenty': '20', 'nineteen': '19', 'eighteen': '18', 'seventeen': '17',
      'sixteen': '16', 'fifteen': '15', 'fourteen': '14', 'thirteen': '13',
      'twelve': '12', 'eleven': '11', 'ten': '10', 'nine': '9', 'eight': '8',
      'seven': '7', 'six': '6', 'five': '5', 'four': '4', 'three': '3',
      'two': '2', 'one': '1', 'zero': '0',
      'thirty': '30', 'forty': '40', 'fifty': '50',
      'o clock': ':00', 'oclock': ':00',
    };
    
    // Sort keys by length (longest first) to match longer phrases before shorter ones
    final sortedKeys = numberMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    
    for (final word in sortedKeys) {
      result = result.replaceAll(
        RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false),
        numberMap[word]!,
      );
    }
    
    // Clean up any repeated spaces
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    
    return result;
  }

  _GuidedFrequency _frequencyFromGuidedSpeech(String value) {
    final normalized = value.trim().toLowerCase();
    final isTagalog = LanguageController.isTagalog.value;
    final customMatch = RegExp(
      r'\b(?:every|kada)\s+(\d{1,2})\s+(?:hour|hours|oras)\b',
    ).firstMatch(normalized);
    if (customMatch != null) {
      final hours = (int.tryParse(customMatch.group(1) ?? '') ?? 1).clamp(
        1,
        10,
      );
      return _GuidedFrequency(
        'custom:${hours * 60}',
        hours * 60,
        isTagalog
            ? 'Kada $hours oras'
            : 'Every $hours ${hours == 1 ? 'hour' : 'hours'}',
      );
    }
    if (_containsAny(normalized, const [
      'one time only',
      'isang beses lamang',
    ])) {
      return _GuidedFrequency(
        'none',
        0,
        isTagalog ? 'Isang beses lamang' : 'One time only',
      );
    }
    if (_containsAny(normalized, const ['araw-araw', 'every day', 'daily'])) {
      return _GuidedFrequency(
        'daily',
        1440,
        isTagalog ? 'Araw-araw' : 'Every day',
      );
    }
    if (_containsAny(normalized, const [
      'umaga at gabi',
      'morning and evening',
    ])) {
      return _GuidedFrequency(
        'custom:720',
        720,
        isTagalog ? 'Umaga at gabi' : 'Morning and evening',
      );
    }
    if (_containsAny(normalized, const [
      'linggo-linggo',
      'every week',
      'weekly',
    ])) {
      return _GuidedFrequency(
        'weekly',
        10080,
        isTagalog ? 'Linggo-linggo' : 'Every week',
      );
    }
    if (_containsAny(normalized, const [
      'twice a week',
      'dalawang beses kada linggo',
    ])) {
      return _GuidedFrequency(
        'custom:5040',
        5040,
        isTagalog ? 'Dalawang beses kada linggo' : 'Twice a week',
      );
    }
    if (_containsAny(normalized, const [
      'buwan-buwan',
      'every month',
      'monthly',
    ])) {
      return _GuidedFrequency(
        'monthly',
        43200,
        isTagalog ? 'Buwan-buwan' : 'Every month',
      );
    }
    if (_containsAny(normalized, const [
      'twice a month',
      'dalawang beses kada buwan',
    ])) {
      return _GuidedFrequency(
        'twice_monthly',
        21600,
        isTagalog ? 'Dalawang beses kada buwan' : 'Twice a month',
      );
    }
    return _GuidedFrequency(
      'none',
      0,
      isTagalog ? 'Isang beses lamang' : 'One time only',
    );
  }

  bool _isNoteKeyword(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'note' ||
        normalized == 'notes' ||
        normalized == 'tala' ||
        normalized.contains('note') ||
        normalized.contains('tala') ||
        normalized.contains('add note') ||
        normalized.contains('magdagdag ng tala');
  }

  bool _isSetTimeKeyword(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.contains('set time') ||
        normalized.contains('itakda ang oras') ||
        normalized.contains('oras');
  }

  bool _isFrequencyKeyword(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.contains('frequency') || normalized.contains('dalas');
  }

  bool _isCustomKeyword(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.contains('custom');
  }

  bool _containsAny(String value, List<String> phrases) {
    return phrases.any(value.contains);
  }

  String _capitalizeGuidedTitle(String value) {
    final title = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (title.isEmpty) return title;
    return title[0].toUpperCase() + title.substring(1);
  }

  Future<void> _speakGuidedReminderSummary(VoiceReminderDraft draft) async {
    final isTagalog = LanguageController.isTagalog.value;
    final summary = tr(
      isTagalog,
      'Reminder summary.\nTitle: ${draft.title}\nNote: ${draft.note.isEmpty ? 'None' : draft.note}\nTime: ${DateFormat('h:mm a').format(draft.scheduledAt)}\nFrequency: ${draft.frequencyLabel}\nWould you like to save this reminder?',
      'Buod ng paalala.\nPamagat: ${draft.title}\nTala: ${draft.note.isEmpty ? 'Wala' : draft.note}\nOras: ${DateFormat('h:mm a').format(draft.scheduledAt)}\nDalas: ${draft.frequencyLabel}\nGusto mo bang i-save ang paalalang ito?',
    );
    await _speechModule.speak(summary);
  }

  Future<void> _confirmVoiceReminder(VoiceReminderDraft draft) async {
    final isTagalog = LanguageController.isTagalog.value;
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(
              tr(isTagalog, 'Confirm Reminder', 'Kumpirmahin ang Paalala'),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDraftDetail(
                    tr(isTagalog, 'Title', 'Pamagat'),
                    draft.title,
                  ),
                  if (draft.note.isNotEmpty)
                    _buildDraftDetail(
                      tr(isTagalog, 'Note', 'Tala'),
                      draft.note,
                    ),
                  _buildDraftDetail(
                    tr(isTagalog, 'Date and Time', 'Petsa at Oras'),
                    DateFormat('MMM d, yyyy h:mm a').format(draft.scheduledAt),
                  ),
                  _buildDraftDetail(
                    tr(isTagalog, 'Frequency', 'Dalas'),
                    draft.frequencyLabel,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 'cancel'),
                          child: Text(tr(isTagalog, 'Cancel', 'Kanselahin')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 'edit'),
                          child: Text(tr(isTagalog, 'Edit', 'I-edit')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, 'save'),
                          child: Text(tr(isTagalog, 'Save', 'I-save')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (action == 'save') {
      await _saveVoiceReminder(draft);
    } else if (action == 'edit') {
      await _editVoiceReminderDraft(draft);
    }

    _resetVoiceIdleState();
  }

  Widget _buildDraftDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.nunitoSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editVoiceReminderDraft(VoiceReminderDraft draft) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddReminderScreen(
          prefillTitle: draft.title,
          prefillDescription: draft.note,
          prefillDate: DateTime(
            draft.scheduledAt.year,
            draft.scheduledAt.month,
            draft.scheduledAt.day,
          ),
          prefillTime: TimeOfDay.fromDateTime(draft.scheduledAt),
          prefillRepeatType: draft.repeatType,
          prefillRepeatIntervalMinutes: draft.repeatIntervalMinutes,
        ),
      ),
    );

    if (updated == true && mounted) {
      await _loadReminders(showLoading: false);
    }
  }

  Future<void> _saveVoiceReminder(VoiceReminderDraft draft) async {
    if (_hasDuplicateVoiceReminder(draft)) {
      await _respondFromAssistant(
        tr(
          LanguageController.isTagalog.value,
          'That reminder already exists, so I did not create a duplicate.',
          'May kaparehong paalala na, kaya hindi ako gumawa ng duplicate.',
        ),
      );
      _resetVoiceIdleState();
      return;
    }

    final now = DateTime.now();
    final reminder = {
      'id': _uuidV4(),
      'title': draft.title,
      'description': draft.note,
      'reminder_time': draft.scheduledAt.toIso8601String(),
      'scheduledTimeMillis': draft.scheduledAt.millisecondsSinceEpoch,
      'category': _categoryForVoiceReminder(draft),
      'repeat_type': draft.repeatType,
      'isRepeating': draft.isRepeating,
      'repeatIntervalMinutes': draft.repeatIntervalMinutes,
      'priority': _categoryForVoiceReminder(draft) == 'pill'
          ? 'high'
          : 'normal',
      'is_completed': false,
      'isCompleted': false,
      'is_canceled': false,
      'isCanceled': false,
      'sync_status': 'queued',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'source': 'voice_assistant',
    };

    await _reminderRepository.saveReminder(reminder);
    await ReminderNotificationService.instance.scheduleReminder(reminder);
    await _loadReminders(showLoading: false);

    await _respondFromAssistant(
      tr(
        LanguageController.isTagalog.value,
        'Reminder saved: ${draft.title} at ${DateFormat('h:mm a').format(draft.scheduledAt)}.',
        'Na-save ang paalala: ${draft.title} sa ${DateFormat('h:mm a').format(draft.scheduledAt)}.',
      ),
    );
  }

  bool _hasDuplicateVoiceReminder(VoiceReminderDraft draft) {
    return _reminders.any((reminder) {
      final sameTitle =
          reminder.title.trim().toLowerCase() ==
          draft.title.trim().toLowerCase();
      final sameTime =
          (reminder.scheduledTimeMillis -
                  draft.scheduledAt.millisecondsSinceEpoch)
              .abs() <
          const Duration(minutes: 1).inMilliseconds;
      final sameRepeat =
          reminder.repeatIntervalMinutes == draft.repeatIntervalMinutes;
      return sameTitle && sameTime && sameRepeat && !reminder.isCanceled;
    });
  }

  Future<void> _answerReminderQuery(ReminderQueryType type) async {
    final isTagalog = LanguageController.isTagalog.value;
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending =
        _reminders
            .where(
              (r) =>
                  !r.isCompleted &&
                  !r.isCompletedToday &&
                  !r.isCanceled &&
                  !r.isSkippedToday &&
                  !r.isMissedToday &&
                  r.scheduledTimeMillis >= now,
            )
            .toList()
          ..sort(
            (a, b) => a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis),
          );

    late final String answer;
    switch (type) {
      case ReminderQueryType.today:
        answer = _insightsService.spokenSchedule(_reminders);
      case ReminderQueryType.next:
        answer = pending.isEmpty
            ? tr(
                isTagalog,
                'You have no upcoming reminders.',
                'Wala kang paparating na paalala.',
              )
            : tr(
                isTagalog,
                'Your next reminder is ${pending.first.title} at ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(pending.first.scheduledTimeMillis))}.',
                'Ang susunod mong paalala ay ${pending.first.title} sa ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(pending.first.scheduledTimeMillis))}.',
              );
      case ReminderQueryType.medicineNow:
        final medicine = pending.where(_isMedicationReminder).toList();
        answer = medicine.isEmpty
            ? tr(
                isTagalog,
                'I do not see medicine due right now.',
                'Wala akong nakikitang gamot na kailangang inumin ngayon.',
              )
            : tr(
                isTagalog,
                'Your next medicine reminder is ${medicine.first.title} at ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(medicine.first.scheduledTimeMillis))}.',
                'Ang susunod mong paalala sa gamot ay ${medicine.first.title} sa ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(medicine.first.scheduledTimeMillis))}.',
              );
      case ReminderQueryType.pendingCount:
        answer = tr(
          isTagalog,
          'You have ${pending.length} pending reminders.',
          'Mayroon kang ${pending.length} na nakabinbing paalala.',
        );
    }

    await _respondFromAssistant(answer);
  }

  Future<void> _respondFromAssistant(String answer) async {
    if (answer.trim().isEmpty) return;
    _showAssistantResponse(answer);
    await _speechModule.speak(answer);
  }

  void _showAssistantResponse(String answer) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  LanguageController.isTagalog.value,
                  'Voice Assistant',
                  'Voice Assistant',
                ),
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(answer, style: GoogleFonts.nunitoSans(fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  bool _isMedicationReminder(ReminderModel reminder) {
    final text = '${reminder.title} ${reminder.description}'.toLowerCase();
    return reminder.category.toLowerCase() == 'pill' ||
        text.contains('medicine') ||
        text.contains('medication') ||
        text.contains('gamot') ||
        text.contains('vitamin');
  }

  String _categoryForVoiceReminder(VoiceReminderDraft draft) {
    return VoiceReminderHints.categoryForText(
      '${draft.title} ${draft.originalText}',
    );
  }

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String byteToHex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final hex = bytes.map(byteToHex).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<void> _showTranslationDialog(String initialText) async {
    final controller = TextEditingController(text: initialText);
    var translatedText = '';
    var toTagalog = !LanguageController.isTagalog.value;
    var isTranslating = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            tr(LanguageController.isTagalog.value, 'Translate', 'Isalin'),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: tr(
                      LanguageController.isTagalog.value,
                      'Text',
                      'Teksto',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    toTagalog ? 'English to Tagalog' : 'Tagalog to English',
                  ),
                  value: toTagalog,
                  onChanged: (value) {
                    setDialogState(() {
                      toTagalog = value;
                      translatedText = '';
                    });
                  },
                ),
                if (translatedText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(translatedText),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: isTranslating
                  ? null
                  : () async {
                      setDialogState(() => isTranslating = true);
                      final result = await _translationProcessor.translateAsync(
                        text: controller.text,
                        toTagalog: toTagalog,
                      );
                      setDialogState(() {
                        translatedText = result.text;
                        isTranslating = false;
                      });
                    },
              child: Text(isTranslating ? 'Translating...' : 'Translate'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
  }

  void _showSnack(String message) {
    if (message.trim().isEmpty || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reportVoiceError(Object error) async {
    _resetVoiceIdleState();
    final message = _friendlyVoiceError(error);
    _showSnack(message);
    try {
      await _speechModule.speak(message);
    } catch (_) {
      // Visual feedback is enough if TTS is unavailable.
    }
  }

  String _friendlyVoiceError(Object error) {
    final raw = error.toString();
    final isTagalog = LanguageController.isTagalog.value;
    if (raw.contains('Groq API key is not configured')) {
      return tr(
        isTagalog,
        'Voice transcription is not configured yet. Please add a Groq API key.',
        'Hindi pa naka-configure ang voice transcription. Ilagay muna ang Groq API key.',
      );
    }
    if (raw.contains('Microphone permission')) {
      return tr(
        isTagalog,
        'Microphone permission is required to use voice reminders.',
        'Kailangan ng microphone permission para sa voice reminders.',
      );
    }
    if (raw.contains('No audio was recorded') ||
        raw.contains('No recording was captured') ||
        raw.contains('No transcription was returned')) {
      return tr(
        isTagalog,
        'I did not catch that. Please try speaking again.',
        'Hindi ko narinig nang malinaw. Pakisubukan ulit magsalita.',
      );
    }
    if (raw.contains('No internet connection')) {
      return tr(
        isTagalog,
        'No internet connection. Voice transcription needs internet.',
        'Walang internet connection. Kailangan ng internet para sa voice transcription.',
      );
    }
    if (raw.contains('timed out') || raw.contains('temporarily unavailable')) {
      return tr(
        isTagalog,
        'Voice transcription is taking too long. Please try again.',
        'Matagal ang voice transcription. Pakisubukan muli.',
      );
    }
    return tr(
      isTagalog,
      'Voice assistant could not finish that. Please try again.',
      'Hindi natapos ng voice assistant ang utos. Pakisubukan muli.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isTagalog,
      builder: (context, isTagalog, child) {
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(theme, isTagalog)),
                  SliverToBoxAdapter(child: _buildTopAction(theme, isTagalog)),
                  SliverToBoxAdapter(
                    child: _buildVoiceStatusPanel(theme, isTagalog),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSusShortcut(theme, isTagalog),
                  ),
                  SliverToBoxAdapter(
                    child: _buildStatusCards(theme, isTagalog),
                  ),
                  SliverToBoxAdapter(
                    child: _buildTodayScheduleSummary(theme, isTagalog),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSectionTitle(theme, isTagalog),
                  ),
                  _buildReminderList(theme),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
          bottomNavigationBar: AppNavigation(
            currentIndex: _currentNavIndex,
            onDestinationSelected: _onNavTap,
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: EmergencyFabWidget(
            contacts: _emergencyContacts,
            countdownEnabled: false,
            countdownSeconds: 3,
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme, bool isTagalog) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? tr(isTagalog, 'Good Morning', 'Magandang Umaga')
        : tr(isTagalog, 'Good Afternoon', 'Magandang Hapon');
    final name = _firstName?.trim();
    final greetingText = name == null || name.isEmpty
        ? '$greeting!'
        : '$greeting, $name!';

    final dateStr = DateFormat('EEEE, MMM d').format(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.profileScreen),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: const AssetImage('assets/images/avatar.png'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greetingText,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  dateStr,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceStatusPanel(ThemeData theme, bool isTagalog) {
    final active = _isListening || _isProcessingVoice;
    final disabled = _isGuidedListening;
    final color = _isListening
        ? AppTheme.errorRed
        : _isProcessingVoice
        ? AppTheme.warning
        : theme.colorScheme.primary;

    if (disabled) {
      return const SizedBox.shrink();
    }

    final title =
        (_isListening || _isProcessingVoice) && _voiceStatus.isNotEmpty
        ? _voiceStatus
        : _isListening
        ? tr(isTagalog, 'Recording...', 'Nagre-record...')
        : _isProcessingVoice
        ? tr(isTagalog, 'Transcribing...', 'Isinasalin sa text...')
        : _liveTranscript.isNotEmpty
        ? tr(isTagalog, 'Voice Result', 'Resulta ng Boses')
        : tr(
            isTagalog,
            'Tap to speak',
            'I-tap para magsalita',
          );
    
    void onTapAction() => unawaited(_onVoiceButtonTap());

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Tooltip(
        message: _isListening || _isProcessingVoice
            ? tr(
                isTagalog,
                'Voice Assistant - Press to stop',
                'Voice Assistant - Pindutin para tumigil',
              )
            : tr(
                isTagalog,
                'Voice Assistant - Press to record',
                'Voice Assistant - Pindutin para mag-record',
              ),
        child: InkWell(
          onTap: onTapAction,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              color: color.withAlpha(active ? 35 : 20),
              border: Border.all(color: color, width: active ? 3 : 2),
              borderRadius: BorderRadius.circular(20),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: color.withAlpha(90),
                        blurRadius: _isListening ? 20 : 10,
                        spreadRadius: _isListening ? 3 : 1,
                      ),
                    ]
                  : null,
            ),
            child: _isProcessingVoice
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        title,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            if (_liveTranscript.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                _liveTranscript,
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 16,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (_voiceParserLabel != null &&
                                !_isListening &&
                                !_isProcessingVoice) ...[
                              const SizedBox(height: 10),
                              _buildVoiceParserBadge(theme, isTagalog),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _isListening
                          ? SizedBox(
                              width: 64,
                              height: 64,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(Icons.graphic_eq, color: color.withAlpha(120), size: 32),
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.82, end: 1.16),
                                    duration: const Duration(milliseconds: 650),
                                    builder: (context, scale, child) {
                                      return Transform.scale(scale: scale, child: child);
                                    },
                                    onEnd: () {
                                      if (mounted && _isListening) setState(() {});
                                    },
                                    child: Icon(Icons.mic, color: color, size: 48),
                                  ),
                                ],
                              ),
                            )
                          : Icon(Icons.mic, color: color, size: 56),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceParserBadge(ThemeData theme, bool isTagalog) {
    final label = _voiceParserLabel;
    if (label == null) return const SizedBox.shrink();

    final badgeColor = _voiceUsedGemma
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final badgeTextColor = _voiceUsedGemma
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final icon = _voiceUsedGemma ? Icons.auto_awesome : Icons.rule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _voiceUsedGemma
                  ? theme.colorScheme.primary.withAlpha(80)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: badgeTextColor),
              const SizedBox(width: 6),
              Text(
                tr(
                  isTagalog,
                  'Parser: $label',
                  'Parser: $label',
                ),
                style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: badgeTextColor,
                ),
              ),
            ],
          ),
        ),
        if (_voiceParserDetail != null && _voiceParserDetail!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _voiceParserDetail!,
            style: GoogleFonts.nunitoSans(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildTopAction(ThemeData theme, bool isTagalog) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: ElevatedButton(
        onPressed: () =>
            Navigator.pushNamed(context, AppRoutes.addReminderScreen),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_alert, size: 28),
            const SizedBox(width: 12),
            Text(
              tr(isTagalog, '+ Add Reminder', '+ Magdagdag ng Paalala'),
              style: GoogleFonts.nunitoSans(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSusShortcut(ThemeData theme, bool isTagalog) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Material(
        color: theme.colorScheme.secondaryContainer.withAlpha(180),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _runSusEvaluation,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.fact_check_outlined,
                    color: theme.colorScheme.secondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          isTagalog,
                          'Evaluate usability',
                          'Suriin ang paggamit',
                        ),
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(
                          isTagalog,
                          'Open the SUS questionnaire',
                          'Buksan ang SUS questionnaire',
                        ),
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSecondaryContainer
                              .withAlpha(190),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _runSusEvaluation() {
    final answers = List<int>.filled(10, 3);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('SUS Evaluation'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_susProcessor.getPurposeDescription()),
                  const SizedBox(height: 8),
                  Text(
                    '1 = Strongly disagree, 5 = Strongly agree',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(SusProcessingModule.questions.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}. ${SusProcessingModule.questions[i]}'),
                          Slider(
                            min: 1,
                            max: 5,
                            divisions: 4,
                            label: answers[i].toString(),
                            value: answers[i].toDouble(),
                            onChanged: (value) {
                              setDialogState(() => answers[i] = value.round());
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Strongly disagree',
                                style: GoogleFonts.nunitoSans(fontSize: 11),
                              ),
                              Text(
                                'Strongly agree',
                                style: GoogleFonts.nunitoSans(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final result = _susProcessor.evaluate(answers);
                await _susProcessor.saveResult(result);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _showSusResult(result);
              },
              child: const Text('Calculate'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSusResult(SusEvaluationResult result) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SUS Result'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SUS Score: ${result.score.toStringAsFixed(1)}\n'
                'Rating: ${result.rating}\n'
                'Interpretation: ${result.interpretation}',
              ),
              const SizedBox(height: 16),
              Text(
                'Recommended improvements',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...result.improvements.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('- $item'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards(ThemeData theme, bool isTagalog) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pendingCount = _reminders
        .where(
          (r) =>
              !r.isCompleted &&
              !r.isCanceled &&
              !r.isSkipped &&
              !r.isMissed &&
              r.scheduledTimeMillis >= now,
        )
        .length;
    final completedCount = _reminders
        .where((r) => r.isCompleted || r.isCompletedToday)
        .length;
    final missedCount = _reminders
        .where(
          (r) =>
              !r.isCompleted &&
              !r.isCanceled &&
              !r.isSkipped &&
              !r.isMissed &&
              r.scheduledTimeMillis < now,
        )
        .length;
    final skippedCount = _reminders.where((r) => r.isSkippedToday).length;
    final missedStatusCount = _reminders.where((r) => r.isMissedToday).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatusCard(
                  theme,
                  title: tr(isTagalog, 'Pending', 'Nakabinbin'),
                  count: pendingCount,
                  icon: Icons.pending_actions,
                  color: Colors.orange.shade100,
                  iconColor: Colors.orange.shade800,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatusCard(
                  theme,
                  title: tr(isTagalog, 'Completed', 'Tapos Na'),
                  count: completedCount,
                  icon: Icons.check_circle_outline,
                  color: Colors.green.shade100,
                  iconColor: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatusCard(
                  theme,
                  title: tr(isTagalog, 'Skipped', 'Nilaktawan'),
                  count: skippedCount,
                  icon: Icons.skip_next_outlined,
                  color: Colors.blue.shade100,
                  iconColor: Colors.blue.shade800,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatusCard(
                  theme,
                  title: tr(isTagalog, 'Missed', 'Nalagpasan'),
                  count: missedStatusCount + missedCount,
                  icon: Icons.error_outline,
                  color: Colors.red.shade100,
                  iconColor: Colors.red.shade800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    ThemeData theme, {
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(height: 12),
          Text(
            count.toString(),
            style: GoogleFonts.nunitoSans(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.nunitoSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayScheduleSummary(ThemeData theme, bool isTagalog) {
    final schedule = _insightsService.todaySchedule(_reminders);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(isTagalog, "Today's Schedule", 'Iskedyul Ngayon'),
                    style: GoogleFonts.nunitoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _readTodaySchedule,
                  icon: const Icon(Icons.volume_up),
                  label: Text(
                    tr(
                      isTagalog,
                      "Read Today's Schedule",
                      'Basahin ang Iskedyul Ngayon',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (schedule.isEmpty)
              Text(
                tr(
                  isTagalog,
                  'No reminders scheduled today.',
                  'Walang paalala ngayong araw.',
                ),
                style: GoogleFonts.nunitoSans(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...schedule
                  .take(6)
                  .map(
                    (reminder) => _buildScheduleRow(theme, isTagalog, reminder),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRow(
    ThemeData theme,
    bool isTagalog,
    ReminderModel reminder,
  ) {
    final scheduled = DateTime.fromMillisecondsSinceEpoch(
      reminder.scheduledTimeMillis,
    );
    final done = reminder.isCompleted || reminder.isCompletedToday;
    final missed =
        reminder.isMissedToday ||
        (!done &&
            !reminder.isCanceled &&
            reminder.scheduledTimeMillis <
                DateTime.now().millisecondsSinceEpoch);
    final icon = done
        ? Icons.check_circle
        : missed
        ? Icons.error_outline
        : Icons.radio_button_unchecked;
    final color = done
        ? AppTheme.success
        : missed
        ? AppTheme.errorRed
        : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              DateFormat('h:mm a').format(scheduled),
              style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              reminder.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunitoSans(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, bool isTagalog) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr(isTagalog, 'Upcoming Reminders', 'Mga Paparating na Paalala'),
              style: GoogleFonts.nunitoSans(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.allRemindersScreen),
            child: Text(
              tr(isTagalog, 'View All', 'Tingnan Lahat'),
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderList(ThemeData theme) {
    if (_isLoading) {
      return const SliverToBoxAdapter(child: ReminderListSkeleton());
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = _reminders
        .where(
          (r) =>
              !r.isCompleted &&
              !r.isCanceled &&
              !r.isSkipped &&
              !r.isMissed &&
              r.scheduledTimeMillis >= now,
        )
        .toList();

    if (pending.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateWidget(
          iconName: 'alarm',
          title: 'No upcoming reminders',
          description: tr(
            LanguageController.isTagalog.value,
            "Tap '+ Add Reminder' to create a new task.",
            "I-tap ang '+ Magdagdag ng Paalala' para gumawa ng bagong gawain.",
          ),
          ctaLabel: tr(
            LanguageController.isTagalog.value,
            'Add Reminder',
            'Magdagdag ng Paalala',
          ),
          onCtaTap: () =>
              Navigator.pushNamed(context, AppRoutes.addReminderScreen),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((ctx, i) {
          final r = pending[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ReminderCardWidget(
              reminder: r,
              onDelete: () => _deleteReminder(r),
              onMarkComplete: () => _markComplete(r),
              onTap: () => _editReminder(r),
            ),
          );
        }, childCount: pending.length),
      ),
    );
  }
}
