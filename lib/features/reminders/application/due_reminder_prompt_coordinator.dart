import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lifeease/core/navigation/app_navigator.dart';
import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/notifications/reminder_notification_service.dart';
import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/features/reminders/models/reminder_model.dart';
import 'package:lifeease/features/voice/application/speech_processing_module.dart';
import 'package:lifeease/shared/providers/language_controller.dart';

class DueReminderPromptCoordinator {
  DueReminderPromptCoordinator._();

  static final DueReminderPromptCoordinator instance =
      DueReminderPromptCoordinator._();

  final ReminderRepository _repository = ReminderRepository();
  final SpeechProcessingModule _speechModule = SpeechProcessingModule();
  final Set<String> _shownDueReminderKeys = <String>{};
  bool _isShowingPrompt = false;

  bool get isShowingPrompt => _isShowingPrompt;

  Future<void> start() async {
    await processPendingDueReminders();
    await _processLaunchNotification();
  }

  Future<void> processPendingDueReminders() async {
    if (_isShowingPrompt) return;

    final events =
        await ReminderNotificationService.instance.drainPendingDueReminders();
    for (final event in events) {
      if (_isShowingPrompt) break;
      await handleDueReminderEvent(event);
    }
  }

  Future<void> handleDueReminderEvent(ReminderDueEvent event) async {
    final reminderId = event.reminder['id']?.toString();
    if (reminderId == null || reminderId.isEmpty) return;

    final key = '$reminderId.${event.scheduledAt.millisecondsSinceEpoch}';
    if (!_shownDueReminderKeys.add(key)) return;

    final reminder = ReminderModel.fromMap({
      ...event.reminder,
      'reminder_time': event.scheduledAt.toIso8601String(),
      'scheduledTimeMillis': event.scheduledAt.millisecondsSinceEpoch,
    });
    await showDueReminderPrompt(reminder);
  }

  Future<void> showRecentlyDueReminderPrompts(
    List<ReminderModel> reminders,
  ) async {
    if (_isShowingPrompt) return;

    final now = DateTime.now();
    for (final reminder in reminders) {
      if (reminder.isCompleted ||
          reminder.isCompletedToday ||
          reminder.isCanceled ||
          reminder.isCanceledToday ||
          reminder.isSkippedToday ||
          reminder.isMissedToday) {
        continue;
      }

      final scheduled = DateTime.fromMillisecondsSinceEpoch(
        reminder.scheduledTimeMillis,
      );
      if (scheduled.isAfter(now)) continue;
      if (now.difference(scheduled) > const Duration(minutes: 5)) continue;

      final key = '${reminder.id}.${scheduled.millisecondsSinceEpoch}';
      if (!_shownDueReminderKeys.add(key)) continue;
      await showDueReminderPrompt(reminder);
      return;
    }
  }

  Future<void> _processLaunchNotification() async {
    final launchDetails =
        await ReminderNotificationService.instance.getNotificationLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (response == null) return;

    await ReminderNotificationService.instance.queueDueReminderFromNotificationTap(
      response,
    );
    await processPendingDueReminders();
  }

  Future<void> showDueReminderPrompt(ReminderModel reminder) async {
    final context = AppNavigator.key.currentContext;
    if (context == null || _isShowingPrompt) return;

    _isShowingPrompt = true;
    final isTagalog = LanguageController.isTagalog.value;

    try {
      final scheduled = DateTime.fromMillisecondsSinceEpoch(
        reminder.scheduledTimeMillis,
      );
      final timeStr = DateFormat('h:mm a').format(scheduled);
      final categoryLabel = _categoryLabel(reminder.category, isTagalog);

      final announcement = isTagalog
          ? 'Paalala na. Kategorya: $categoryLabel. ${reminder.title}. ${reminder.description.isNotEmpty ? reminder.description : 'Walang karagdagang detalye'}. Oras: $timeStr.'
          : 'Reminder due. Category: $categoryLabel. ${reminder.title}. ${reminder.description.isNotEmpty ? reminder.description : 'No additional details'}. Time: $timeStr.';
      unawaited(_speechModule.speak(announcement));

      final action = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_active,
                color: theme.colorScheme.primary,
                size: 28,
              ),
            ),
            title: Text(
              isTagalog ? 'Oras Na Ng Paalala' : 'Reminder Due',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunitoSans(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    categoryLabel,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  reminder.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (reminder.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    reminder.description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeStr,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'cancel'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        isTagalog ? 'Kanselahin' : 'Cancel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunitoSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'skip'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        isTagalog ? 'Laktawan' : 'Skip',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunitoSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'done'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        isTagalog ? 'Tapos' : 'Done',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunitoSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );

      if (action == 'done') {
        await _markComplete(reminder);
      } else if (action == 'skip') {
        await _markSkipped(reminder);
      } else if (action == 'cancel') {
        await _markCanceled(reminder);
      }
    } finally {
      _isShowingPrompt = false;
    }
  }

  Future<void> _markComplete(ReminderModel reminder) async {
    await _repository.markReminderComplete(reminder.toMap());
    if (reminder.isRepeating) {
      final updated = await _repository.loadReminderById(reminder.id);
      if (updated != null) {
        await ReminderNotificationService.instance.scheduleReminder(updated);
      }
    } else {
      await ReminderNotificationService.instance.cancelReminder(reminder.id);
    }
  }

  Future<void> _markSkipped(ReminderModel reminder) async {
    await _repository.markReminderSkipped(reminder.toMap());
    if (reminder.isRepeating) {
      final updated = await _repository.loadReminderById(reminder.id);
      if (updated != null) {
        await ReminderNotificationService.instance.scheduleReminder(updated);
      }
    } else {
      await ReminderNotificationService.instance.cancelReminder(reminder.id);
    }
  }

  Future<void> _markCanceled(ReminderModel reminder) async {
    await _repository.markReminderCanceled(reminder.toMap());
    await ReminderNotificationService.instance.cancelReminder(reminder.id);
  }

  String _categoryLabel(String category, bool isTagalog) {
    switch (category.toLowerCase()) {
      case 'health':
        return isTagalog ? 'Kalusugan' : 'Health';
      case 'medical':
        return isTagalog ? 'Medikal' : 'Medical';
      case 'work':
        return isTagalog ? 'Trabaho' : 'Work';
      case 'personal':
        return isTagalog ? 'Personal' : 'Personal';
      case 'family':
        return isTagalog ? 'Pamilya' : 'Family';
      case 'appointment':
        return isTagalog ? 'Appointment' : 'Appointment';
      case 'meeting':
        return isTagalog ? 'Meeting' : 'Meeting';
      case 'shopping':
        return isTagalog ? 'Pamimili' : 'Shopping';
      case 'exercise':
        return isTagalog ? 'Ehersisyo' : 'Exercise';
      case 'medication':
        return isTagalog ? 'Gamot' : 'Medication';
      default:
        return isTagalog ? 'Pangkalahatan' : 'General';
    }
  }
}

class DueReminderPromptListener extends StatefulWidget {
  const DueReminderPromptListener({super.key, required this.child});

  final Widget child;

  @override
  State<DueReminderPromptListener> createState() =>
      _DueReminderPromptListenerState();
}

class _DueReminderPromptListenerState extends State<DueReminderPromptListener>
    with WidgetsBindingObserver {
  StreamSubscription<ReminderDueEvent>? _dueReminderEvents;
  Timer? _pendingDueDrainTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dueReminderEvents = ReminderNotificationService.instance.dueReminders.listen(
      (event) {
        unawaited(DueReminderPromptCoordinator.instance.handleDueReminderEvent(event));
      },
    );
    _pendingDueDrainTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(DueReminderPromptCoordinator.instance.processPendingDueReminders());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(DueReminderPromptCoordinator.instance.start());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dueReminderEvents?.cancel();
    _pendingDueDrainTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DueReminderPromptCoordinator.instance.processPendingDueReminders());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
