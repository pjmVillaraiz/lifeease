import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/notifications/reminder_notification_service.dart';
import 'package:lifeease/core/services/supabase_config.dart';
import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/features/reminders/presentation/add_reminder_screen/add_reminder_screen.dart';
import 'package:lifeease/features/reminders/models/reminder_model.dart';
import 'package:lifeease/shared/providers/language_controller.dart';
import 'package:lifeease/shared/widgets/app_navigation.dart';
import 'package:lifeease/shared/widgets/empty_state_widget.dart';
import 'package:lifeease/shared/widgets/loading_skeleton_widget.dart';

enum ReminderFilter { all, pending, completed, skipped, missed }

class AllRemindersScreen extends StatefulWidget {
  const AllRemindersScreen({super.key});

  @override
  State<AllRemindersScreen> createState() => _AllRemindersScreenState();
}

class _AllRemindersScreenState extends State<AllRemindersScreen>
    with WidgetsBindingObserver {
  final ReminderRepository _reminderRepository = ReminderRepository();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  final DateFormat _timeFormat = DateFormat('h:mm a');

  bool _isLoading = true;
  ReminderFilter _filter = ReminderFilter.all;
  List<ReminderModel> _reminders = [];
  List<Map<String, dynamic>> _adherenceHistory = [];
  DateTime _selectedDate = DateTime.now();
  late final StreamSubscription<void> _reminderChanges;

  String tr(bool isTagalog, String en, String tl) => isTagalog ? tl : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminderChanges = ReminderRepository.changes.listen((_) {
      _loadReminders(showLoading: false);
    });
    _loadReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderChanges.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadReminders(showLoading: false);
    }
  }

  Future<void> _loadReminders({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() => _isLoading = true);
    }
    final rows = await _reminderRepository.loadReminders();
    final history = await _reminderRepository.loadAdherenceHistory();
    unawaited(_reminderRepository.syncQueuedReminders());
    if (!mounted) return;

    final loaded = rows.map(ReminderModel.fromMap).toList()
      ..sort((a, b) => a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis));

    setState(() {
      _reminders = loaded;
      _adherenceHistory = history;
      _isLoading = false;
    });
  }

  Future<void> _deleteReminder(ReminderModel reminder) async {
    setState(() => _reminders.removeWhere((r) => r.id == reminder.id));
    await _reminderRepository.deleteReminder(reminder.id);
    await ReminderNotificationService.instance.cancelReminder(reminder.id);
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
    if (reminder.isRepeating) {
      final nextReminder = await _reminderRepository.loadReminderById(
        reminder.id,
      );
      if (nextReminder != null) {
        await ReminderNotificationService.instance.scheduleReminder(
          nextReminder,
        );
      }
      await _loadReminders(showLoading: false);
    } else {
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

  bool _isMissed(ReminderModel reminder) {
    return !reminder.isCompleted &&
        !reminder.isCanceled &&
        !reminder.isSkipped &&
        !reminder.isMissed &&
        reminder.scheduledTimeMillis < DateTime.now().millisecondsSinceEpoch;
  }

  List<ReminderModel> get _filteredReminders {
    switch (_filter) {
      case ReminderFilter.pending:
        return _reminders
            .where(
              (r) =>
                  !r.isCompleted &&
                  !r.isCanceled &&
                  !r.isSkipped &&
                  !r.isMissed &&
                  !_isMissed(r),
            )
            .toList();
      case ReminderFilter.completed:
        return _reminders
            .where((r) => r.isCompleted || r.isCompletedToday)
            .toList();
      case ReminderFilter.skipped:
        return _reminders.where((r) => r.isSkippedToday).toList();
      case ReminderFilter.missed:
        return _reminders
            .where((r) => r.isMissedToday || _isMissed(r))
            .toList();
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
                SliverToBoxAdapter(
                  child: _buildAdherenceHistory(theme, isTagalog),
                ),
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
    final total = _reminders.length;
    final pending = _reminders
        .where(
          (r) =>
              !r.isCompleted &&
              !r.isCanceled &&
              !r.isSkipped &&
              !r.isMissed &&
              !_isMissed(r),
        )
        .length;
    final completed = _reminders
        .where((r) => r.isCompleted || r.isCompletedToday)
        .length;
    final skipped = _reminders.where((r) => r.isSkippedToday).length;
    final missed = _reminders
        .where((r) => r.isMissedToday || _isMissed(r))
        .length;
    final completionRate = total == 0
        ? 0
        : ((completed / total) * 100).round().clamp(0, 100);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(
                        isTagalog,
                        'Reminder Statistics',
                        'Estadistika ng Paalala',
                      ),
                      style: GoogleFonts.nunitoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${tr(isTagalog, 'Completion', 'Natapos')}: '
                    '$completionRate%',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildSummaryItem(
                  theme,
                  label: tr(isTagalog, 'Total', 'Lahat'),
                  count: total,
                  icon: Icons.list_alt_rounded,
                ),
                _buildSummaryItem(
                  theme,
                  label: tr(isTagalog, 'Pending', 'Pending'),
                  count: pending,
                  icon: Icons.pending_actions_rounded,
                ),
                _buildSummaryItem(
                  theme,
                  label: tr(isTagalog, 'Done', 'Tapos'),
                  count: completed,
                  icon: Icons.check_circle_outline_rounded,
                ),
                _buildSummaryItem(
                  theme,
                  label: tr(isTagalog, 'Skipped', 'Laktaw'),
                  count: skipped,
                  icon: Icons.skip_next_outlined,
                ),
                _buildSummaryItem(
                  theme,
                  label: tr(isTagalog, 'Missed', 'Miss'),
                  count: missed,
                  icon: Icons.error_outline_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdherenceHistory(ThemeData theme, bool isTagalog) {
    final entries = _timelineEntriesForDate(_selectedDate);
    final completed = entries.where((e) => e.status == 'completed').length;
    final score = entries.isEmpty
        ? 0
        : ((completed / entries.length) * 100).round().clamp(0, 100);
    final weekScore = _adherenceScoreForRange(
      _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1)),
      _selectedDate.add(Duration(days: 7 - _selectedDate.weekday)),
    );
    final monthStart = DateTime(_selectedDate.year, _selectedDate.month);
    final monthEnd = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final monthScore = _adherenceScoreForRange(monthStart, monthEnd);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                    tr(
                      isTagalog,
                      'Adherence History',
                      'Kasaysayan ng Pagsunod',
                    ),
                    style: GoogleFonts.nunitoSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickHistoryDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_dateFormat.format(_selectedDate)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickDateChip(
                  theme,
                  label: tr(isTagalog, 'Today', 'Ngayon'),
                  date: DateTime.now(),
                ),
                _buildQuickDateChip(
                  theme,
                  label: tr(isTagalog, 'Yesterday', 'Kahapon'),
                  date: DateTime.now().subtract(const Duration(days: 1)),
                ),
                _buildQuickDateChip(
                  theme,
                  label: tr(isTagalog, 'Last Week', 'Nakaraang Linggo'),
                  date: DateTime.now().subtract(const Duration(days: 7)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _AdherenceMetric(
                    label: tr(isTagalog, 'Daily', 'Araw'),
                    value: '$score%',
                  ),
                ),
                Expanded(
                  child: _AdherenceMetric(
                    label: tr(isTagalog, 'Weekly', 'Linggo'),
                    value: '$weekScore%',
                  ),
                ),
                Expanded(
                  child: _AdherenceMetric(
                    label: tr(isTagalog, 'Monthly', 'Buwan'),
                    value: '$monthScore%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              tr(isTagalog, 'Timeline', 'Timeline'),
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text(
                tr(
                  isTagalog,
                  'No reminder activity for this date.',
                  'Walang activity ng paalala sa petsang ito.',
                ),
                style: GoogleFonts.nunitoSans(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...entries.map(
                (entry) => _AdherenceTimelineRow(
                  entry: entry,
                  timeFormat: _timeFormat,
                  isTagalog: isTagalog,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickDateChip(
    ThemeData theme, {
    required String label,
    required DateTime date,
  }) {
    final selected = _isSameDay(_selectedDate, date);
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() => _selectedDate = date),
      selectedColor: AppTheme.primaryBlue,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      labelStyle: GoogleFonts.nunitoSans(
        fontWeight: FontWeight.w800,
        color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _pickHistoryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  List<_AdherenceEntry> _timelineEntriesForDate(DateTime date) {
    final dateKey = _dateKey(date);
    final entries = <String, _AdherenceEntry>{};

    for (final row in _adherenceHistory) {
      if (row['date_key']?.toString() != dateKey) continue;
      final entry = _AdherenceEntry.fromMap(row);
      entries[entry.id] = entry;
    }

    for (final reminder in _reminders) {
      final scheduled = DateTime.fromMillisecondsSinceEpoch(
        reminder.scheduledTimeMillis,
      );
      final occurrenceId = '${reminder.id}.${scheduled.millisecondsSinceEpoch}';

      if (reminder.lastOccurrenceDate == dateKey &&
          reminder.lastOccurrenceStatus.isNotEmpty) {
        entries.putIfAbsent(
          occurrenceId,
          () => _AdherenceEntry(
            id: occurrenceId,
            reminderId: reminder.id,
            title: reminder.title,
            scheduledAt: scheduled,
            status: reminder.lastOccurrenceStatus,
          ),
        );
      }

      if (_isSameDay(scheduled, date) &&
          !entries.containsKey(occurrenceId) &&
          !reminder.isCanceled) {
        entries[occurrenceId] = _AdherenceEntry(
          id: occurrenceId,
          reminderId: reminder.id,
          title: reminder.title,
          scheduledAt: scheduled,
          status: _statusForReminderOnDate(reminder, date),
        );
      }
    }

    final sorted = entries.values.toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return sorted;
  }

  int _adherenceScoreForRange(DateTime start, DateTime end) {
    var total = 0;
    var completed = 0;
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      final entries = _timelineEntriesForDate(cursor);
      total += entries.length;
      completed += entries.where((e) => e.status == 'completed').length;
      cursor = cursor.add(const Duration(days: 1));
    }
    if (total == 0) return 0;
    return ((completed / total) * 100).round().clamp(0, 100);
  }

  String _statusForReminderOnDate(ReminderModel reminder, DateTime date) {
    if (reminder.lastOccurrenceDate == _dateKey(date) &&
        reminder.lastOccurrenceStatus.isNotEmpty) {
      return reminder.lastOccurrenceStatus;
    }
    if (reminder.isCompleted) return 'completed';
    if (reminder.isSkipped) return 'skipped';
    if (reminder.isMissed || _isMissed(reminder)) return 'missed';
    return 'pending';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
            label: tr(isTagalog, 'Skipped', 'Nilaktawan'),
            filter: ReminderFilter.skipped,
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
            isTagalog: isTagalog,
            dateFormat: _dateFormat,
            timeFormat: _timeFormat,
            onDelete: () => _deleteReminder(reminder),
            onEdit: () => _editReminder(reminder),
            onMarkComplete:
                reminder.isCompleted || reminder.isCanceled || reminder.isMissed
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

class _AdherenceEntry {
  const _AdherenceEntry({
    required this.id,
    required this.reminderId,
    required this.title,
    required this.scheduledAt,
    required this.status,
  });

  final String id;
  final String reminderId;
  final String title;
  final DateTime scheduledAt;
  final String status;

  factory _AdherenceEntry.fromMap(Map<String, dynamic> map) {
    final scheduledValue = map['scheduled_at'];
    final scheduledAt = scheduledValue is int
        ? DateTime.fromMillisecondsSinceEpoch(scheduledValue)
        : DateTime.tryParse(map['scheduled_time']?.toString() ?? '') ??
              DateTime.now();
    return _AdherenceEntry(
      id: map['id']?.toString() ?? '',
      reminderId: map['reminder_id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Reminder',
      scheduledAt: scheduledAt,
      status: map['status']?.toString() ?? 'pending',
    );
  }
}

class _AdherenceMetric extends StatelessWidget {
  const _AdherenceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdherenceTimelineRow extends StatelessWidget {
  const _AdherenceTimelineRow({
    required this.entry,
    required this.timeFormat,
    required this.isTagalog,
  });

  final _AdherenceEntry entry;
  final DateFormat timeFormat;
  final bool isTagalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(entry.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              timeFormat.format(entry.scheduledAt),
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(_statusIcon(entry.status), size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _statusLabel(entry.status),
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return isTagalog ? 'Tapos Na' : 'Completed';
      case 'skipped':
        return isTagalog ? 'Nilaktawan' : 'Skipped';
      case 'missed':
        return isTagalog ? 'Nalagpasan' : 'Missed';
      default:
        return isTagalog ? 'Nakabinbin' : 'Pending';
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_rounded;
      case 'skipped':
        return Icons.skip_next_rounded;
      case 'missed':
        return Icons.close_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppTheme.success;
      case 'skipped':
        return AppTheme.primaryBlue;
      case 'missed':
        return AppTheme.errorRed;
      default:
        return Colors.orange.shade800;
    }
  }
}

class _ReminderListTile extends StatelessWidget {
  final ReminderModel reminder;
  final bool isMissed;
  final bool isSynced;
  final bool isTagalog;
  final DateFormat dateFormat;
  final DateFormat timeFormat;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onMarkComplete;

  const _ReminderListTile({
    required this.reminder,
    required this.isMissed,
    required this.isSynced,
    required this.isTagalog,
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
    final accent = reminder.isCanceled || reminder.isCanceledToday
        ? theme.colorScheme.outline
        : reminder.isCompleted || reminder.isCompletedToday
        ? AppTheme.success
        : reminder.isSkippedToday
        ? AppTheme.primaryBlue
        : reminder.isMissedToday
        ? AppTheme.errorRed
        : isMissed
        ? AppTheme.errorRed
        : AppTheme.primaryBlue;
    final statusLabel = reminder.isCanceled || reminder.isCanceledToday
        ? TtsLanguageService.canceledLabel()
        : reminder.isCompleted || reminder.isCompletedToday
        ? (isTagalog ? 'Tapos Na' : 'Completed')
        : reminder.isSkippedToday
        ? (isTagalog ? 'Nilaktawan' : 'Skipped')
        : reminder.isMissedToday
        ? (isTagalog ? 'Nalagpasan' : 'Missed')
        : isMissed
        ? (isTagalog ? 'Nalagpasan' : 'Missed')
        : (isTagalog ? 'Nakabinbin' : 'Pending');

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
                        '${TtsLanguageService.descriptionLabel()}: '
                        '${reminder.description}',
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
