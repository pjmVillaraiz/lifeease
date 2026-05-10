import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/shared/providers/language_controller.dart';
import 'package:lifeease/shared/widgets/app_navigation.dart';
import 'package:lifeease/shared/widgets/emergency_fab_widget.dart';
import 'package:lifeease/shared/widgets/empty_state_widget.dart';
import 'package:lifeease/shared/widgets/loading_skeleton_widget.dart';

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/features/voice/application/speech_processing_module.dart';
import 'package:lifeease/features/voice/application/voice_command_processing_module.dart';

import './widgets/reminder_card_widget.dart';

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
  bool _isListening = false;

  late final ReminderRepository _reminderRepository;
  late final SpeechProcessingModule _speechModule;
  late final VoiceCommandProcessingModule _voiceProcessor;

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
    _speechModule = SpeechProcessingModule();
    _voiceProcessor = VoiceCommandProcessingModule();
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

    _listEntranceController.forward(from: 0.0);
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _loadReminders();
  }

  Future<void> _deleteReminder(ReminderModel reminder) async {
    setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
    await _reminderRepository.deleteReminder(reminder.id);
  }

  Future<void> _markComplete(ReminderModel reminder) async {
    setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
    await _reminderRepository.markReminderComplete(reminder.toMap());
    HapticFeedback.mediumImpact();
  }

  Future<void> _onSpeakCommand() async {
    HapticFeedback.heavyImpact();
    setState(() => _isListening = true);
    final spokenText = await _speechModule.listenOnce();
    if (!mounted) return;

    setState(() => _isListening = false);
    if (spokenText != null && spokenText.isNotEmpty) {
      await _handleCommandText(spokenText);
    }
  }

  Future<void> _handleCommandText(String input) async {
    final result = await _voiceProcessor.parseAsync(input);
    if (!mounted) return;

    if (result.type == VoiceIntentType.addReminder) {
      Navigator.pushNamed(
        context,
        AppRoutes.addReminderScreen,
        arguments: {'prefillTitle': result.task},
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Command recognized: \${result.task}')),
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
    if (index == 4) {
      Navigator.pushNamed(context, AppRoutes.settingsScreen).then((_) {
        setState(() => _currentNavIndex = 0);
      });
    }
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
                  SliverToBoxAdapter(child: _buildStatusCards(theme, isTagalog)),
                  SliverToBoxAdapter(child: _buildSectionTitle(theme, isTagalog)),
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
        : now.hour < 17
            ? tr(isTagalog, 'Good Afternoon', 'Magandang Hapon')
            : tr(isTagalog, 'Good Evening', 'Magandang Gabi');

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
                  '$greeting, User!',
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
        onPressed: () => Navigator.pushNamed(context, AppRoutes.addReminderScreen),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  Widget _buildStatusCards(ThemeData theme, bool isTagalog) {
    final pendingCount = _reminders.where((r) => !r.isCompleted).length;
    final completedCount = _reminders.where((r) => r.isCompleted).length;
    // Mock values for missed and cancelled as they are not explicitly tracked in DB yet
    final missedCount = 0;
    final cancelledCount = 0;

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
                  title: tr(isTagalog, 'Missed', 'Nalagpasan'),
                  count: missedCount,
                  icon: Icons.error_outline,
                  color: Colors.red.shade100,
                  iconColor: Colors.red.shade800,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatusCard(
                  theme,
                  title: tr(isTagalog, 'Cancelled', 'Kinansela'),
                  count: cancelledCount,
                  icon: Icons.cancel_outlined,
                  color: Colors.grey.shade300,
                  iconColor: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme,
      {required String title, required int count, required IconData icon, required Color color, required Color iconColor}) {
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
            '\$count',
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
      child: Text(
        tr(isTagalog, 'Upcoming Reminders', 'Mga Paparating na Paalala'),
        style: GoogleFonts.nunitoSans(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildReminderList(ThemeData theme) {
    if (_isLoading) {
      return const SliverToBoxAdapter(child: ReminderListSkeleton());
    }

    final pending = _reminders.where((r) => !r.isCompleted).toList();

    if (pending.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateWidget(
          iconName: 'alarm',
          title: 'No upcoming reminders',
          description: "Tap '+ Add Reminder' to create a new task.",
          ctaLabel: 'Add Reminder',
          onCtaTap: () => Navigator.pushNamed(context, AppRoutes.addReminderScreen),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final r = pending[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ReminderCardWidget(
                reminder: r,
                onDelete: () => _deleteReminder(r),
                onMarkComplete: () => _markComplete(r),
                onTap: () => Navigator.pushNamed(context, AppRoutes.addReminderScreen),
              ),
            );
          },
          childCount: pending.length,
        ),
      ),
    );
  }
}
