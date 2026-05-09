import 'package:flutter/services.dart';

import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/shared/providers/language_controller.dart';
import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/shared/widgets/app_navigation.dart';
import 'package:lifeease/shared/widgets/emergency_fab_widget.dart';
import 'package:lifeease/shared/widgets/empty_state_widget.dart';
import 'package:lifeease/shared/widgets/loading_skeleton_widget.dart';
import 'package:lifeease/features/scheduling/domain/rule_based_scheduling_engine.dart';
import 'package:lifeease/features/translation/application/language_translation_processing_module.dart';
import 'package:lifeease/features/voice/application/speech_processing_module.dart';
import 'package:lifeease/features/voice/application/voice_command_processing_module.dart';
import 'package:lifeease/features/accessibility/presentation/settings_screen/settings_screen.dart';
import 'package:lifeease/features/accessibility/presentation/profile_screen/profile_screen.dart';
import './widgets/big_button_row_widget.dart';
import './widgets/home_header_widget.dart';
import './widgets/reminder_card_widget.dart';
import './widgets/suggestion_card_widget.dart';

class ReminderModel {
  final String id;
  final String title;
  final String description;
  final int scheduledTimeMillis;
  final bool isCompleted;
  final bool isRepeating;
  final int repeatIntervalMinutes;
  final String category;
  final String userUid;
  final int createdAt;
  final bool isSynced;

  const ReminderModel({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTimeMillis,
    required this.isCompleted,
    required this.isRepeating,
    required this.repeatIntervalMinutes,
    required this.category,
    required this.userUid,
    required this.createdAt,
    required this.isSynced,
  });

  factory ReminderModel.fromMap(Map<String, dynamic> map) {
    final scheduledAt = map['scheduledTimeMillis'] ?? map['reminder_time'];
    final createdValue = map['createdAt'] ?? map['created_at'];

    return ReminderModel(
      id: map['id']?.toString() ?? DateTime.now().toIso8601String(),
      title: map['title']?.toString() ?? 'Reminder',
      description: map['description']?.toString() ?? '',
      scheduledTimeMillis: _millisFromValue(scheduledAt),
      isCompleted:
          map['isCompleted'] as bool? ?? map['is_completed'] as bool? ?? false,
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
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'scheduledTimeMillis': scheduledTimeMillis,
    'isCompleted': isCompleted,
    'isRepeating': isRepeating,
    'repeatIntervalMinutes': repeatIntervalMinutes,
    'category': category,
    'userUid': userUid,
    'createdAt': createdAt,
    'isSynced': isSynced,
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
    switch (repeatType) {
      case 'daily':
        return 1440;
      case 'weekly':
        return 10080;
      case 'monthly':
        return 43200;
      default:
        return 0;
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentNavIndex = 0;
  bool _isLoading = true;
  List<ReminderModel> _reminders = [];
  bool _showSuggestion = true;
  final int _suggestionHour = 8;
  bool _isListening = false;

  // Production: Initialize services
  late final ReminderRepository _reminderRepository;
  late final SpeechProcessingModule _speechModule;
  late final VoiceCommandProcessingModule _voiceProcessor;
  late final LanguageTranslationProcessingModule _translationProcessor;
  late final RuleBasedSchedulingEngine _schedulingEngine;

  String tr(bool isTagalog, String en, String tl) {
    return isTagalog ? tl : en;
  }

  late AnimationController _listEntranceController;
  late List<Animation<double>> _itemAnimations;

  static const List<EmergencyContact> _emergencyContacts = [
    EmergencyContact(
      id: 1,
      name: 'Maria Santos',
      phone: '+639171234567',
      relationship: 'Daughter',
      priority: 1,
    ),
    EmergencyContact(
      id: 2,
      name: 'Dr. Reyes',
      phone: '+639281234567',
      relationship: 'Doctor',
      priority: 2,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _listEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Initialize services
    _reminderRepository = ReminderRepository();
    _speechModule = SpeechProcessingModule();
    _voiceProcessor = VoiceCommandProcessingModule();
    _translationProcessor = LanguageTranslationProcessingModule();
    _schedulingEngine = RuleBasedSchedulingEngine();
    _loadReminders();
  }

  @override
  void dispose() {
    _listEntranceController.dispose();
    super.dispose();
  }

  Future<void> _loadReminders() async {
    if (!mounted) return;

    final rows = await _reminderRepository.loadReminders();
    if (!mounted) return;

    final loaded = rows.map(ReminderModel.fromMap).toList();
    loaded.sort(
      (a, b) => a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis),
    );

    setState(() {
      _reminders = loaded;
      _isLoading = false;
    });

    _itemAnimations = List.generate(
      _reminders.length,
      (i) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _listEntranceController,
          curve: Interval(
            (i * 0.08).clamp(0.0, 0.7),
            ((i * 0.08) + 0.4).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
    );
    _listEntranceController.forward();
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _loadReminders();
  }

  Future<void> _deleteReminder(ReminderModel reminder) async {
    setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
    await _reminderRepository.deleteReminder(reminder.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reminder deleted',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppTheme.primaryBlueDark,
          onPressed: () async {
            setState(() {
              _reminders.add(reminder);
              _reminders.sort(
                (a, b) =>
                    a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis),
              );
            });
            await _reminderRepository.saveReminder(reminder.toMap());
          },
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _markComplete(ReminderModel reminder) async {
    setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
    await _reminderRepository.markReminderComplete(reminder.toMap());
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✓ Reminder marked as complete',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onSpeakCommand() async {
    HapticFeedback.heavyImpact();
    setState(() => _isListening = true);
    final spokenText = await _speechModule.listenOnce();
    if (!mounted) return;

    setState(() => _isListening = false);
    if (spokenText != null && spokenText.isNotEmpty) {
      await _handleCommandText(spokenText);
      return;
    }
    await _showManualCommandDialog();
  }

  Future<void> _handleCommandText(String input) async {
    final result = await _voiceProcessor.parseAsync(input);
    if (!mounted) return;

    String message;
    switch (result.type) {
      case VoiceIntentType.addReminder:
        message = "Reminder command recognized: ${result.task}";
        Navigator.pushNamed(
          context,
          AppRoutes.addReminderScreen,
          arguments: {'prefillTitle': result.task},
        );
        break;
      case VoiceIntentType.callEmergency:
        message =
            "Emergency command recognized. Tap Call Family to confirm safely.";
        break;
      case VoiceIntentType.translate:
        final translated = await _translationProcessor.translateAsync(
          text: input,
          toTagalog: !LanguageController.isTagalog.value,
        );
        message = "Translation: ${translated.text}";
        break;
      case VoiceIntentType.summarize:
        message = "Summary: ${result.summary}";
        break;
      case VoiceIntentType.unknown:
        message =
            "Command not recognized. Try add reminder, translate, or summarize.";
        break;
    }

    if (!mounted) return;
    final structured = result.toJson();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "$message\nAI: ${structured['intent']} • confidence ${(result.confidence * 100).round()}%",
          style: GoogleFonts.nunitoSans(fontSize: 14),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _speechModule.speak(message);
  }

  Future<void> _showManualCommandDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          "Voice Command Processing Module",
          style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Type command, e.g. remind me at 8 AM",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _handleCommandText(controller.text);
            },
            child: const Text("Process"),
          ),
        ],
      ),
    );
  }

  void _onNotificationTap() {
    final pendingItems = _reminders
        .where((r) => !r.isCompleted)
        .map((r) => r.title)
        .toList();
    final summary = _voiceProcessor.summarizeText(pendingItems.join(". "));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          summary.isEmpty
              ? "No pending reminders."
              : "Reminder summary: $summary",
          style: GoogleFonts.nunitoSans(fontSize: 14),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onNavTap(int index) {
    if (index == 0) {
      setState(() => _currentNavIndex = 0);
    } else if (index == 1) {
      setState(() => _currentNavIndex = 1);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ).then((_) {
        setState(() => _currentNavIndex = 0);
      });
    } else if (index == 2) {
      setState(() => _currentNavIndex = 2);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ).then((_) {
        setState(() => _currentNavIndex = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isTagalog,
      builder: (context, isTagalog, child) {
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppTheme.primaryBlue,
              strokeWidth: 2.5,
              displacement: 40,
              child: isTablet
                  ? _buildTabletLayout(theme, isTagalog: isTagalog)
                  : _buildPhoneLayout(theme, isTagalog: isTagalog),
            ),
          ),
          bottomNavigationBar: AppNavigation(
            currentIndex: _currentNavIndex,
            onDestinationSelected: _onNavTap,
          ),
          floatingActionButton: EmergencyFabWidget(
            contacts: _emergencyContacts,
            countdownEnabled: false,
            countdownSeconds: 3,
          ),
        );
      },
    );
  }

  Widget _buildPhoneLayout(ThemeData theme, {required bool isTagalog}) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              HomeHeaderWidget(
                userName: 'Lola Nena',
                pendingCount: _reminders.length,
                onNotificationTap: _onNotificationTap,
                onAvatarTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BigButtonRowWidget(
                  onAddReminder: () =>
                      Navigator.pushNamed(context, AppRoutes.addReminderScreen),
                  onSpeakCommand: _onSpeakCommand,
                  isListening: _isListening,
                ),
              ),
              if (_showSuggestion) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SuggestionCardWidget(
                    suggestedHour: _suggestionHour,
                    isTagalog: isTagalog,
                    onAddNow: (hour) {
                      final suggestion = _schedulingEngine.buildSuggestion(
                        category: "pill",
                        isRepeating: true,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            suggestion.note,
                            style: GoogleFonts.nunitoSans(fontSize: 13),
                          ),
                        ),
                      );
                      Navigator.pushNamed(
                        context,
                        AppRoutes.addReminderScreen,
                        arguments: {'prefillHour': hour},
                      );
                    },
                    onDismiss: () => setState(() => _showSuggestion = false),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildSectionHeader(theme, isTagalog: isTagalog),
            ],
          ),
        ),
        _buildReminderList(theme, isTablet: false),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildTabletLayout(ThemeData theme, {required bool isTagalog}) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              HomeHeaderWidget(
                userName: 'Lola Nena',
                pendingCount: _reminders.length,
                onNotificationTap: _onNotificationTap,
                onAvatarTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: BigButtonRowWidget(
                  onAddReminder: () =>
                      Navigator.pushNamed(context, AppRoutes.addReminderScreen),
                  onSpeakCommand: _onSpeakCommand,
                  isListening: _isListening,
                  isTablet: true,
                ),
              ),
              if (_showSuggestion) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SuggestionCardWidget(
                    suggestedHour: _suggestionHour,
                    isTagalog: isTagalog,
                    onAddNow: (hour) {
                      final suggestion = _schedulingEngine.buildSuggestion(
                        category: "pill",
                        isRepeating: true,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            suggestion.note,
                            style: GoogleFonts.nunitoSans(fontSize: 13),
                          ),
                        ),
                      );
                      Navigator.pushNamed(
                        context,
                        AppRoutes.addReminderScreen,
                        arguments: {'prefillHour': hour},
                      );
                    },
                    onDismiss: () => setState(() => _showSuggestion = false),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildSectionHeader(theme, isTablet: true, isTagalog: isTagalog),
            ],
          ),
        ),
        _buildReminderList(theme, isTablet: true),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme, {
    bool isTablet = false,
    bool isTagalog = false,
  }) {
    final pending = _reminders.where((r) => !r.isCompleted).length;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            tr(isTagalog, "Today's Reminders", 'Mga Paalala Ngayon'),
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (pending > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$pending pending',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReminderList(ThemeData theme, {required bool isTablet}) {
    if (_isLoading) {
      return const SliverToBoxAdapter(child: ReminderListSkeleton());
    }

    if (_reminders.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateWidget(
          iconName: 'alarm',
          title: 'No reminders yet',
          description:
              "Tap 'Add Reminder' to create your first health reminder.",
          ctaLabel: 'Add Reminder',
          onCtaTap: () =>
              Navigator.pushNamed(context, AppRoutes.addReminderScreen),
        ),
      );
    }

    if (isTablet) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _buildAnimatedCard(i, theme),
            childCount: _reminders.length,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildAnimatedCard(i, theme),
          ),
          childCount: _reminders.length,
        ),
      ),
    );
  }

  Widget _buildAnimatedCard(int index, ThemeData theme) {
    if (index >= _itemAnimations.length) {
      return ReminderCardWidget(
        reminder: _reminders[index],
        onDelete: () => _deleteReminder(_reminders[index]),
        onMarkComplete: () => _markComplete(_reminders[index]),
        onTap: () => Navigator.pushNamed(context, AppRoutes.addReminderScreen),
      );
    }

    return FadeTransition(
      opacity: _itemAnimations[index],
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _listEntranceController,
                curve: Curves.easeOutCubic,
              ),
            ),
        child: ReminderCardWidget(
          reminder: _reminders[index],
          onDelete: () => _deleteReminder(_reminders[index]),
          onMarkComplete: () => _markComplete(_reminders[index]),
          onTap: () =>
              Navigator.pushNamed(context, AppRoutes.addReminderScreen),
        ),
      ),
    );
  }
}
