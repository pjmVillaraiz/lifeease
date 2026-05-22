import 'dart:async';

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
import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/features/reminders/presentation/add_reminder_screen/add_reminder_screen.dart';
import 'package:lifeease/features/sus_evaluation/application/sus_processing_module.dart';
import 'package:lifeease/features/translation/application/language_translation_processing_module.dart';
import 'package:lifeease/features/voice/application/speech_processing_module.dart';
import 'package:lifeease/features/voice/application/voice_command_processing_module.dart';

import './widgets/reminder_card_widget.dart';

class ReminderModel {
  final String id;
  final String title;
  final String description;
  final int scheduledTimeMillis;
  final bool isCompleted;
  final bool isCanceled;
  final bool isSkipped;
  final bool isMissed;
  final bool isRepeating;
  final int repeatIntervalMinutes;
  final String category;
  final String userUid;
  final int createdAt;
  final bool isSynced;
  final String lastOccurrenceStatus;
  final String lastOccurrenceDate;

  const ReminderModel({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTimeMillis,
    required this.isCompleted,
    required this.isCanceled,
    required this.isSkipped,
    required this.isMissed,
    required this.isRepeating,
    required this.repeatIntervalMinutes,
    required this.category,
    required this.userUid,
    required this.createdAt,
    required this.isSynced,
    this.lastOccurrenceStatus = '',
    this.lastOccurrenceDate = '',
  });

  factory ReminderModel.fromMap(Map<String, dynamic> map) {
    final scheduledAt = map['scheduledTimeMillis'] ?? map['reminder_time'];
    final createdValue = map['createdAt'] ?? map['created_at'];

    return ReminderModel(
      id: map['id']?.toString() ?? DateTime.now().toIso8601String(),
      title: map['title']?.toString() ?? TtsLanguageService.reminderLabel(),
      description: map['description']?.toString() ?? '',
      scheduledTimeMillis: _millisFromValue(scheduledAt),
      isCompleted:
          map['isCompleted'] as bool? ?? map['is_completed'] as bool? ?? false,
      isCanceled:
          map['isCanceled'] as bool? ??
          map['is_canceled'] as bool? ??
          (map['sync_status'] == 'canceled' ||
              map['sync_status'] == 'cancelled' ||
              map['task_status'] == 'cancelled'),
      isSkipped:
          map['isSkipped'] as bool? ??
          (map['task_status'] == 'skipped' ||
              map['last_occurrence_status'] == 'skipped'),
      isMissed:
          map['isMissed'] as bool? ??
          (map['task_status'] == 'missed' ||
              map['last_occurrence_status'] == 'missed'),
      isRepeating:
          map['isRepeating'] as bool? ??
          ((map['repeat_type']?.toString() ?? '').isNotEmpty &&
              map['repeat_type'] != 'none'),
      repeatIntervalMinutes:
          map['repeatIntervalMinutes'] as int? ??
          _repeatMinutesFromType(map['repeat_type']?.toString()),
      category: map['category'] as String? ?? 'general',
      userUid: map['userUid'] as String? ?? '',
      createdAt: _millisFromValue(createdValue),
      isSynced: map['isSynced'] as bool? ?? map['sync_status'] == 'synced',
      lastOccurrenceStatus: map['last_occurrence_status']?.toString() ?? '',
      lastOccurrenceDate: map['last_occurrence_date']?.toString() ?? '',
    );
  }

  bool get isCompletedToday {
    return lastOccurrenceStatus == 'completed' &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  bool get isCanceledToday {
    return (lastOccurrenceStatus == 'cancelled' ||
            lastOccurrenceStatus == 'canceled') &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  bool get isSkippedToday {
    if (isSkipped && !isRepeating) return true;
    return (isSkipped || lastOccurrenceStatus == 'skipped') &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  bool get isMissedToday {
    if (isMissed && !isRepeating) return true;
    return (isMissed || lastOccurrenceStatus == 'missed') &&
        lastOccurrenceDate == _dateKey(DateTime.now());
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'scheduledTimeMillis': scheduledTimeMillis,
    'reminder_time': DateTime.fromMillisecondsSinceEpoch(
      scheduledTimeMillis,
    ).toIso8601String(),
    'isCompleted': isCompleted,
    'isCanceled': isCanceled,
    'is_canceled': isCanceled,
    'isSkipped': isSkipped,
    'isMissed': isMissed,
    'task_status': isCanceled
        ? 'cancelled'
        : isSkipped
        ? 'skipped'
        : isMissed
        ? 'missed'
        : 'active',
    'isRepeating': isRepeating,
    'repeatIntervalMinutes': repeatIntervalMinutes,
    'repeat_type': isRepeating
        ? _repeatTypeFromMinutes(repeatIntervalMinutes)
        : 'none',
    'category': category,
    'userUid': userUid,
    'createdAt': createdAt,
    'isSynced': isSynced,
    'last_occurrence_status': lastOccurrenceStatus,
    'last_occurrence_date': lastOccurrenceDate,
  };

  static int _millisFromValue(Object? value) {
    if (value is int) return value;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ??
          int.tryParse(value) ??
          DateTime.now().millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  static int _repeatMinutesFromType(String? repeatType) {
    final customMatch = RegExp(
      r'^custom:(\d+)$',
    ).firstMatch(repeatType?.toLowerCase() ?? '');
    if (customMatch != null) {
      return int.tryParse(customMatch.group(1)!) ?? 0;
    }

    switch (repeatType) {
      case 'daily':
        return 1440;
      case 'twice_monthly':
        return 21600;
      case 'weekly':
        return 10080;
      case 'monthly':
        return 43200;
      default:
        return 0;
    }
  }

  static String _repeatTypeFromMinutes(int minutes) {
    if (minutes == 43200) return 'monthly';
    if (minutes == 21600) return 'twice_monthly';
    if (minutes == 10080) return 'weekly';
    if (minutes == 1440) return 'daily';
    return 'custom:$minutes';
  }

  static String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _currentNavIndex = 0;
  bool _isLoading = true;
  List<ReminderModel> _reminders = [];
  bool _isListening = false;
  String? _firstName;

  late final ReminderRepository _reminderRepository;
  late final SupabaseAuthService _authService;
  late final UserProfileService _profileService;
  late final SpeechProcessingModule _speechModule;
  late final VoiceCommandProcessingModule _voiceProcessor;
  late final LanguageTranslationProcessingModule _translationProcessor;
  late final EmergencyRouteProcessingModule _emergencyRouteProcessor;
  late final SusProcessingModule _susProcessor;
  late final StreamSubscription<void> _reminderChanges;
  Timer? _statusRefreshTimer;
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
    _voiceProcessor = VoiceCommandProcessingModule();
    _translationProcessor = LanguageTranslationProcessingModule();
    _emergencyRouteProcessor = EmergencyRouteProcessingModule();
    _susProcessor = SusProcessingModule();
    WidgetsBinding.instance.addObserver(this);
    _reminderChanges = ReminderRepository.changes.listen((_) {
      _loadReminders(showLoading: false);
    });
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _reconcileDueReminders();
    });
    _loadReminders();
    _loadProfileName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderChanges.cancel();
    _statusRefreshTimer?.cancel();
    _listEntranceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadReminders(showLoading: false);
      _loadProfileName();
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
      await ReminderNotificationService.instance.schedulePendingReminders(rows);
      rows = await _reminderRepository.loadReminders();
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

  Future<void> _onSpeakCommand() async {
    HapticFeedback.heavyImpact();
    setState(() => _isListening = true);
    try {
      final spokenText = await _speechModule.listenOnce();
      if (!mounted) return;

      if (spokenText != null && spokenText.isNotEmpty) {
        await _handleCommandText(spokenText);
      } else {
        _showSnack(
          tr(
            LanguageController.isTagalog.value,
            'No speech was heard. Please try again.',
            'Walang narinig na boses. Subukan muli.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  Future<void> _handleCommandText(String input) async {
    final result = await _voiceProcessor.parseAsync(input);
    if (!mounted) return;

    if (result.type == VoiceIntentType.addReminder) {
      Navigator.pushNamed(
        context,
        AppRoutes.addReminderScreen,
        arguments: {
          'prefillTitle': result.task,
          'prefillTime': _timeOfDayFromVoiceTime(result.time),
        },
      );
      return;
    }

    if (result.type == VoiceIntentType.callEmergency) {
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
      return;
    }

    if (result.type == VoiceIntentType.translate) {
      await _showTranslationDialog(result.task.isEmpty ? input : result.task);
      return;
    }

    if (result.type == VoiceIntentType.summarize) {
      _showSnack(result.summary);
      return;
    }

    _showSnack(
      tr(
        LanguageController.isTagalog.value,
        'Command not recognized. Try "add reminder to take medicine at 8 AM".',
        'Hindi nakilala ang utos. Subukan: "magdagdag ng paalala uminom ng gamot 8 AM".',
      ),
    );
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
      _onSpeakCommand();
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

  TimeOfDay? _timeOfDayFromVoiceTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '') ?? 0;
    final minute = int.tryParse(match.group(2) ?? '') ?? 0;
    final suffix = (match.group(3) ?? '').toUpperCase();
    if (suffix == 'PM' && hour < 12) hour += 12;
    if (suffix == 'AM' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour, minute: minute);
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
                    child: _buildSusShortcut(theme, isTagalog),
                  ),
                  SliverToBoxAdapter(
                    child: _buildStatusCards(theme, isTagalog),
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
          IconButton(
            icon: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              size: 32,
              color: _isListening ? Colors.red : theme.colorScheme.primary,
            ),
            onPressed: _onSpeakCommand,
            tooltip: 'Voice Assistant',
          ),
        ],
      ),
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
