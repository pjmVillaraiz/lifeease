import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/supabase_config.dart';
import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/features/reminders/presentation/add_reminder_screen/add_reminder_screen.dart';
import 'package:lifeease/features/reminders/presentation/home_screen/home_screen.dart';
import 'package:lifeease/shared/providers/language_controller.dart';
import 'package:lifeease/shared/widgets/app_navigation.dart';
import 'package:lifeease/shared/widgets/empty_state_widget.dart';
import 'package:lifeease/shared/widgets/loading_skeleton_widget.dart';

enum ReminderFilter { all, pending, completed, missed }

class AllRemindersScreen extends StatefulWidget {
  const AllRemindersScreen({super.key});

  @override
  State<AllRemindersScreen> createState() => _AllRemindersScreenState();
}

class _AllRemindersScreenState extends State<AllRemindersScreen> {
  final ReminderRepository _reminderRepository = ReminderRepository();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  final DateFormat _timeFormat = DateFormat('h:mm a');

  bool _isLoading = true;
  ReminderFilter _filter = ReminderFilter.all;
  List<ReminderModel> _reminders = [];

  String tr(bool isTagalog, String en, String tl) => isTagalog ? tl : en;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    await _reminderRepository.syncQueuedReminders();
    final rows = await _reminderRepository.loadReminders();
    if (!mounted) return;

    final loaded = rows.map(ReminderModel.fromMap).toList()
      ..sort((a, b) => a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis));

    setState(() {
      _reminders = loaded;
      _isLoading = false;
    });
  }

  Future<void> _deleteReminder(ReminderModel reminder) async {
    setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
    await _reminderRepository.deleteReminder(reminder.id);
    HapticFeedback.mediumImpact();
  }

  Future<void> _markComplete(ReminderModel reminder) async {
    final updated = reminder.toMap()
      ..['isCompleted'] = true
      ..['is_completed'] = true;

    setState(() {
      final index = _reminders.indexWhere((r) => r.id == reminder.id);
      if (index != -1) {
        _reminders[index] = ReminderModel.fromMap(updated);
      }
    });

    await _reminderRepository.markReminderComplete(updated);
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

  bool _isMissed(ReminderModel reminder) {
    return !reminder.isCompleted &&
        reminder.scheduledTimeMillis < DateTime.now().millisecondsSinceEpoch;
  }

  List<ReminderModel> get _filteredReminders {
    switch (_filter) {
      case ReminderFilter.pending:
        return _reminders
            .where((r) => !r.isCompleted && !_isMissed(r))
            .toList();
      case ReminderFilter.completed:
        return _reminders.where((r) => r.isCompleted).toList();
      case ReminderFilter.missed:
        return _reminders.where(_isMissed).toList();
      case ReminderFilter.all:
        return _reminders;
    }
  }

  void _onNavTap(int index) {
    if (index == 1) return;

    if (index == 0) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.homeScreen,
        (route) => false,
      );
      return;
    }

    if (index == 4) {
      Navigator.pushNamed(context, AppRoutes.settingsScreen);
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
          appBar: AppBar(
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            scrolledUnderElevation: 2,
            leading: IconButton(
              icon: CustomIconWidget(
                iconName: 'arrow_back',
                color: theme.colorScheme.onSurface,
                size: 24,
              ),
              onPressed: () => Navigator.pop(context),
              tooltip: tr(isTagalog, 'Back', 'Bumalik'),
            ),
            title: Text(
              tr(isTagalog, 'All Reminders', 'Lahat ng Paalala'),
              style: GoogleFonts.nunitoSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            actions: [
              IconButton(
                onPressed: _loadReminders,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: tr(isTagalog, 'Refresh', 'I-refresh'),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadReminders,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildSummary(theme, isTagalog)),
                SliverToBoxAdapter(child: _buildFilters(theme, isTagalog)),
                _buildReminderList(theme, isTagalog),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
          bottomNavigationBar: AppNavigation(
            currentIndex: 1,
            onDestinationSelected: _onNavTap,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.addReminderScreen),
            icon: const Icon(Icons.add_alert_rounded),
            label: Text(
              tr(isTagalog, 'Add Reminder', 'Magdagdag'),
              style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummary(ThemeData theme, bool isTagalog) {
    final pending = _reminders.where((r) => !r.isCompleted).length;
    final completed = _reminders.where((r) => r.isCompleted).length;
    final missed = _reminders.where(_isMissed).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _buildSummaryItem(
              theme,
              label: tr(isTagalog, 'Pending', 'Pending'),
              count: pending,
              icon: Icons.pending_actions_rounded,
            ),
            _buildSummaryDivider(theme),
            _buildSummaryItem(
              theme,
              label: tr(isTagalog, 'Done', 'Tapos'),
              count: completed,
              icon: Icons.check_circle_outline_rounded,
            ),
            _buildSummaryDivider(theme),
            _buildSummaryItem(
              theme,
              label: tr(isTagalog, 'Missed', 'Missed'),
              count: missed,
              icon: Icons.error_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    ThemeData theme, {
    required String label,
    required int count,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primaryBlue, size: 24),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 58,
      color: theme.colorScheme.onSurface.withAlpha(25),
    );
  }

  Widget _buildFilters(ThemeData theme, bool isTagalog) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildFilterChip(
            theme,
            label: tr(isTagalog, 'All', 'Lahat'),
            filter: ReminderFilter.all,
          ),
          _buildFilterChip(
            theme,
            label: tr(isTagalog, 'Pending', 'Pending'),
            filter: ReminderFilter.pending,
          ),
          _buildFilterChip(
            theme,
            label: tr(isTagalog, 'Completed', 'Tapos Na'),
            filter: ReminderFilter.completed,
          ),
          _buildFilterChip(
            theme,
            label: tr(isTagalog, 'Missed', 'Missed'),
            filter: ReminderFilter.missed,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    ThemeData theme, {
    required String label,
    required ReminderFilter filter,
  }) {
    final selected = _filter == filter;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _filter = filter),
        labelStyle: GoogleFonts.nunitoSans(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
        ),
        selectedColor: AppTheme.primaryBlue,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(
          color: selected ? AppTheme.primaryBlue : theme.colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildReminderList(ThemeData theme, bool isTagalog) {
    if (_isLoading) {
      return const SliverToBoxAdapter(child: ReminderListSkeleton());
    }

    final reminders = _filteredReminders;
    if (reminders.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateWidget(
          iconName: 'alarm',
          title: tr(isTagalog, 'No reminders yet', 'Wala pang paalala'),
          description: tr(
            isTagalog,
            'Add a reminder and it will appear here.',
            'Magdagdag ng paalala at lalabas ito dito.',
          ),
          ctaLabel: tr(isTagalog, 'Add Reminder', 'Magdagdag ng Paalala'),
          onCtaTap: () =>
              Navigator.pushNamed(context, AppRoutes.addReminderScreen),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      sliver: SliverList.separated(
        itemBuilder: (context, index) {
          final reminder = reminders[index];
          return _ReminderListTile(
            reminder: reminder,
            isMissed: _isMissed(reminder),
            isSynced: SupabaseConfig.isInitialized && reminder.isSynced,
            dateFormat: _dateFormat,
            timeFormat: _timeFormat,
            onDelete: () => _deleteReminder(reminder),
            onEdit: () => _editReminder(reminder),
            onMarkComplete: reminder.isCompleted
                ? null
                : () => _markComplete(reminder),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: reminders.length,
      ),
    );
  }
}

class _ReminderListTile extends StatelessWidget {
  final ReminderModel reminder;
  final bool isMissed;
  final bool isSynced;
  final DateFormat dateFormat;
  final DateFormat timeFormat;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onMarkComplete;

  const _ReminderListTile({
    required this.reminder,
    required this.isMissed,
    required this.isSynced,
    required this.dateFormat,
    required this.timeFormat,
    required this.onDelete,
    required this.onEdit,
    required this.onMarkComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduled = DateTime.fromMillisecondsSinceEpoch(
      reminder.scheduledTimeMillis,
    );
    final accent = reminder.isCompleted
        ? AppTheme.success
        : isMissed
        ? AppTheme.errorRed
        : AppTheme.primaryBlue;
    final statusLabel = reminder.isCompleted
        ? 'Completed'
        : isMissed
        ? 'Missed'
        : 'Pending';

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_categoryIcon(reminder.category), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (reminder.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        reminder.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          height: 1.35,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _InfoPill(
                          icon: Icons.schedule_rounded,
                          label:
                              '${dateFormat.format(scheduled)} - ${timeFormat.format(scheduled)}',
                        ),
                        _InfoPill(
                          icon: Icons.label_outline_rounded,
                          label: reminder.category,
                        ),
                        _InfoPill(
                          icon: isSynced
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                          label: isSynced ? 'Synced' : 'Local',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(26),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'complete') onMarkComplete?.call();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 10),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      if (onMarkComplete != null)
                        const PopupMenuItem(
                          value: 'complete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text('Mark complete'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 20),
                            SizedBox(width: 10),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'pill':
        return Icons.medication_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'appointment':
        return Icons.local_hospital_rounded;
      case 'calendar':
        return Icons.event_rounded;
      case 'shopping':
        return Icons.shopping_cart_rounded;
      default:
        return Icons.list_alt_rounded;
    }
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
