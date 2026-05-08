import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_icon_widget.dart';
import '../../../widgets/status_badge_widget.dart';
import '../home_screen.dart';

class ReminderCardWidget extends StatefulWidget {
  final ReminderModel reminder;
  final VoidCallback onDelete;
  final VoidCallback onMarkComplete;
  final VoidCallback onTap;

  const ReminderCardWidget({
    super.key,
    required this.reminder,
    required this.onDelete,
    required this.onMarkComplete,
    required this.onTap,
  });

  @override
  State<ReminderCardWidget> createState() => _ReminderCardWidgetState();
}

class _ReminderCardWidgetState extends State<ReminderCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _dismissController;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _dismissController.dispose();
    super.dispose();
  }

  bool get _isOverdue {
    final now = DateTime.now().millisecondsSinceEpoch;
    return widget.reminder.scheduledTimeMillis < now && !widget.reminder.isCompleted;
  }

  String _formatTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dtDate = DateTime(dt.year, dt.month, dt.day);

    String timeStr;
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    final minute = dt.minute.toString().padLeft(2, '0');
    timeStr = '$hour:$minute $amPm';

    if (dtDate == today) return 'Today, $timeStr';
    if (dtDate == tomorrow) return 'Tomorrow, $timeStr';
    return '${dt.month}/${dt.day}, $timeStr';
  }

  (String, Color, String) _getCategoryInfo() {
    switch (widget.reminder.category.toLowerCase()) {
      case 'pill': return ('💊', AppTheme.categoryPill, 'medication');
      case 'food': return ('🍽️', AppTheme.categoryFood, 'restaurant');
      case 'appointment': return ('🏥', AppTheme.categoryAppointment, 'local_hospital');
      case 'calendar': return ('📅', AppTheme.categoryCalendar, 'event');
      case 'shopping': return ('🛒', AppTheme.categoryShopping, 'shopping_cart');
      default: return ('📋', AppTheme.categoryGeneral, 'list_alt');
    }
  }

  BadgeStatus get _badgeStatus {
    if (_isOverdue) return BadgeStatus.overdue;
    final minutesUntil = (widget.reminder.scheduledTimeMillis - DateTime.now().millisecondsSinceEpoch) ~/ 60000;
    if (minutesUntil < 30) return BadgeStatus.warning;
    return BadgeStatus.pending;
  }

  String get _badgeLabel {
    if (_isOverdue) return 'Overdue';
    final minutesUntil = (widget.reminder.scheduledTimeMillis - DateTime.now().millisecondsSinceEpoch) ~/ 60000;
    if (minutesUntil < 60) return 'Soon';
    return 'Pending';
  }

  void _showContextMenu(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const CustomIconWidget(iconName: 'edit', color: AppTheme.primaryBlue, size: 20),
                ),
                title: Text('Edit Reminder', style: GoogleFonts.nunitoSans(fontSize: 16, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onTap();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.successContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const CustomIconWidget(iconName: 'check_circle', color: AppTheme.success, size: 20),
                ),
                title: Text('Mark Complete', style: GoogleFonts.nunitoSans(fontSize: 16, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onMarkComplete();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const CustomIconWidget(iconName: 'delete_outlined', color: AppTheme.errorRed, size: 20),
                ),
                title: Text('Delete', style: GoogleFonts.nunitoSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.errorRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (emoji, categoryColor, iconName) = _getCategoryInfo();

    return Dismissible(
      key: Key('reminder_${widget.reminder.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        widget.onDelete();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppTheme.errorRed,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CustomIconWidget(iconName: 'delete', color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text('Delete', style: GoogleFonts.nunitoSans(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showContextMenu(context);
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: _isOverdue
                ? Border.all(color: AppTheme.errorRed.withAlpha(102), width: 1.5)
                : Border.all(color: theme.colorScheme.outlineVariant, width: 1),
            boxShadow: [
              BoxShadow(
                color: _isOverdue
                    ? AppTheme.errorRed.withAlpha(20)
                    : Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Left category color bar
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: _isOverdue ? AppTheme.errorRed : categoryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                // Category icon
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: (_isOverdue ? AppTheme.errorRed : categoryColor).withAlpha(31),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.reminder.title,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.reminder.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.reminder.description,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 13,
                              color: theme.colorScheme.outline,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            CustomIconWidget(
                              iconName: 'schedule',
                              color: _isOverdue ? AppTheme.errorRed : theme.colorScheme.outline,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatTime(widget.reminder.scheduledTimeMillis),
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _isOverdue ? AppTheme.errorRed : theme.colorScheme.outline,
                              ),
                            ),
                            if (widget.reminder.isRepeating) ...[
                              const SizedBox(width: 8),
                              CustomIconWidget(
                                iconName: 'repeat',
                                color: AppTheme.secondaryTeal,
                                size: 13,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Trailing badge + action
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusBadgeWidget(
                        status: _badgeStatus,
                        label: _badgeLabel,
                        compact: true,
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _showContextMenu(context),
                        child: CustomIconWidget(
                          iconName: 'more_vert',
                          color: theme.colorScheme.outline,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
