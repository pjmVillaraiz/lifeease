import 'dart:math';

import 'package:flutter/services.dart';

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/backend/user_profile_service.dart';
import 'package:lifeease/core/services/notifications/reminder_notification_service.dart';
import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/features/reminders/application/location_reminder_service.dart';
import 'package:lifeease/features/scheduling/domain/rule_based_scheduling_engine.dart';
import 'package:lifeease/shared/widgets/emergency_fab_widget.dart';
import './widgets/category_chip_row_widget.dart';
import './widgets/date_time_picker_widget.dart';
import './widgets/form_section_card_widget.dart';
import './widgets/repeat_settings_widget.dart';

class AddReminderScreen extends StatefulWidget {
  final int? prefillHour;
  final String? prefillTitle;
  final String? prefillDescription;
  final DateTime? prefillDate;
  final TimeOfDay? prefillTime;
  final String? prefillRepeatType;
  final int? prefillRepeatIntervalMinutes;
  final Map<String, dynamic>? editReminder;

  const AddReminderScreen({
    super.key,
    this.prefillHour,
    this.prefillTitle,
    this.prefillDescription,
    this.prefillDate,
    this.prefillTime,
    this.prefillRepeatType,
    this.prefillRepeatIntervalMinutes,
    this.editReminder,
  });

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationNameController = TextEditingController();

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _selectedCategory = 'general';
  bool _isRepeating = false;
  bool _locationEnabled = false;
  String _locationTrigger = 'arrive';
  double? _locationLatitude;
  double? _locationLongitude;
  int _repeatIntervalMinutes = 60;
  bool _isSaving = false;
  bool _hasChangedSchedule = false;
  final ReminderRepository _reminderRepository = ReminderRepository();
  final RuleBasedSchedulingEngine _schedulingEngine =
      RuleBasedSchedulingEngine();
  final UserProfileService _profileService = UserProfileService();
  List<EmergencyContact> _emergencyContacts = const [];

  String? _titleError;
  String? _timeError;

  bool get _isEditing => widget.editReminder != null;

  late AnimationController _entranceController;
  late Animation<double> _formFade;
  late Animation<Offset> _formSlide;

  @override
  void initState() {
    super.initState();

    final editReminder = widget.editReminder;
    final editScheduled = _dateTimeFromValue(
      editReminder?['reminder_time'] ?? editReminder?['scheduledTimeMillis'],
    );

    _selectedDate = editScheduled ?? widget.prefillDate ?? DateTime.now();
    _selectedTime = editScheduled != null
        ? TimeOfDay.fromDateTime(editScheduled)
        : widget.prefillTime ??
              (widget.prefillHour != null
                  ? TimeOfDay(hour: widget.prefillHour!, minute: 0)
                  : TimeOfDay(
                      hour: (TimeOfDay.now().hour + 1) % 24,
                      minute: 0,
                    ));

    if (editReminder != null) {
      _titleController.text = editReminder['title']?.toString() ?? '';
      _descriptionController.text =
          editReminder['description']?.toString() ?? '';
      _selectedCategory = editReminder['category']?.toString() ?? 'general';
      _isRepeating =
          editReminder['isRepeating'] as bool? ??
          editReminder['is_repeating'] as bool? ??
          ((editReminder['repeat_type']?.toString() ?? 'none') != 'none');
      _repeatIntervalMinutes =
          editReminder['repeatIntervalMinutes'] as int? ??
          _repeatMinutesFromType(editReminder['repeat_type']?.toString());
      _locationEnabled = editReminder['location_enabled'] == true;
      _locationTrigger = editReminder['location_trigger']?.toString() == 'leave'
          ? 'leave'
          : 'arrive';
      _locationNameController.text =
          editReminder['location_name']?.toString() ?? '';
      _locationLatitude = _doubleFrom(editReminder['location_latitude']);
      _locationLongitude = _doubleFrom(editReminder['location_longitude']);
    } else if (widget.prefillTitle != null) {
      _titleController.text = widget.prefillTitle!;
      _descriptionController.text = widget.prefillDescription ?? '';
      final repeatType = widget.prefillRepeatType ?? 'none';
      _isRepeating = repeatType != 'none';
      _repeatIntervalMinutes =
          widget.prefillRepeatIntervalMinutes ??
          _repeatMinutesFromType(repeatType);
    }

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _formFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _formSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
    );
    _entranceController.forward();
    _loadEmergencyContacts();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _locationNameController.dispose();
    super.dispose();
  }

  Future<void> _loadEmergencyContacts() async {
    final contacts = await _profileService.loadEmergencyContacts();
    if (!mounted) return;

    setState(
      () => _emergencyContacts = contacts.asMap().entries.map((entry) {
        final index = entry.key;
        final contact = entry.value;
        return EmergencyContact(
          name: contact.name,
          phone: contact.phone,
          relationship: contact.relationship,
          priority: index + 1,
        );
      }).toList(),
    );
  }

  bool _isTimeInPast() {
    final now = DateTime.now();
    final scheduled = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    return scheduled.isBefore(now);
  }

  String get _reminderLabel => TtsLanguageService.reminderLabel();

  String get _noteLabel => TtsLanguageService.descriptionLabel();

  Future<void> _saveReminder() async {
    setState(() {
      _titleError = null;
      _timeError = null;
    });

    bool valid = true;
    if (_titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Please enter a reminder title');
      valid = false;
    }
    if ((!_isEditing || _hasChangedSchedule) && _isTimeInPast()) {
      setState(() => _timeError = 'Scheduled time cannot be in the past');
      valid = false;
    }
    if (_locationEnabled &&
        (_locationLatitude == null || _locationLongitude == null)) {
      setState(() => _timeError = 'Use current location before saving');
      valid = false;
    }
    if (!valid) {
      HapticFeedback.lightImpact();
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final scheduled = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final existing = widget.editReminder;
    final existingReminders = await _loadScheduledReminders(
      exceptId: existing?['id']?.toString(),
    );
    final decision = _schedulingEngine.evaluate(
      SchedulingRequest(
        title: _titleController.text.trim(),
        category: _selectedCategory,
        scheduledAt: scheduled,
        isRepeating: _isRepeating,
        repeatIntervalMinutes: _repeatIntervalMinutes,
        priority: _selectedCategory == 'pill'
            ? ReminderPriority.high
            : ReminderPriority.normal,
      ),
      existingReminders,
    );

    if (!decision.allowed) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _selectedDate = DateTime(
          decision.scheduledAt.year,
          decision.scheduledAt.month,
          decision.scheduledAt.day,
        );
        _selectedTime = TimeOfDay.fromDateTime(decision.scheduledAt);
        _timeError = decision.hardViolations.first;
      });
      _showSchedulingConflictSnackBar(decision);
      HapticFeedback.lightImpact();
      return;
    }

    final now = DateTime.now();
    final reminderId = existing?['id']?.toString() ?? _uuidV4();
    final createdAt =
        existing?['created_at']?.toString() ?? now.toIso8601String();
    final isCompleted =
        existing?['isCompleted'] as bool? ??
        existing?['is_completed'] as bool? ??
        false;
    final isCanceled =
        existing?['isCanceled'] as bool? ??
        existing?['is_canceled'] as bool? ??
        existing?['sync_status'] == 'canceled';

    final savedReminder = {
      'id': reminderId,
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'reminder_time': decision.scheduledAt.toIso8601String(),
      'scheduledTimeMillis': decision.scheduledAt.millisecondsSinceEpoch,
      'category': _selectedCategory,
      'repeat_type': _isRepeating ? _repeatTypeFromMinutes() : 'none',
      'isRepeating': _isRepeating,
      'repeatIntervalMinutes': _isRepeating ? _repeatIntervalMinutes : 0,
      'priority': decision.priority.name,
      'is_completed': isCompleted,
      'isCompleted': isCompleted,
      'is_canceled': isCanceled,
      'isCanceled': isCanceled,
      'sync_status': isCanceled ? 'canceled' : 'queued',
      'created_at': createdAt,
      'updated_at': now.toIso8601String(),
      'location_enabled': _locationEnabled,
      'location_trigger': _locationTrigger,
      'location_name': _locationNameController.text.trim(),
      'location_latitude': _locationLatitude,
      'location_longitude': _locationLongitude,
      'location_radius_meters': 180,
    };

    await _reminderRepository.saveReminder(savedReminder);
    await ReminderNotificationService.instance.scheduleReminder(savedReminder);

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              decision.softWarnings.isEmpty
                  ? (_isEditing
                        ? '$_reminderLabel updated'
                        : '$_reminderLabel saved')
                  : (_isEditing
                        ? '$_reminderLabel updated with scheduling suggestion'
                        : '$_reminderLabel saved with scheduling suggestion'),
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    if (_isEditing) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.homeScreen,
        (route) => false,
      );
    }
  }

  Future<List<ScheduledReminder>> _loadScheduledReminders({
    String? exceptId,
  }) async {
    final reminders = await _reminderRepository.loadReminders();
    final scheduled = <ScheduledReminder>[];

    for (final reminder in reminders) {
      if (reminder['id']?.toString() == exceptId) continue;
      if (reminder['is_completed'] == true || reminder['isCompleted'] == true) {
        continue;
      }
      if (reminder['is_canceled'] == true || reminder['isCanceled'] == true) {
        continue;
      }

      final scheduledAt = _dateTimeFromValue(
        reminder['reminder_time'] ?? reminder['scheduledTimeMillis'],
      );
      if (scheduledAt == null) continue;

      scheduled.add(
        ScheduledReminder(
          title: reminder['title']?.toString() ?? '',
          category: reminder['category']?.toString() ?? 'general',
          scheduledAt: scheduledAt,
          priority: _priorityFromValue(reminder['priority']),
        ),
      );
    }

    return scheduled;
  }

  ReminderPriority _priorityFromValue(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return ReminderPriority.values.firstWhere(
      (priority) => priority.name == normalized,
      orElse: () => ReminderPriority.normal,
    );
  }

  void _showSchedulingConflictSnackBar(SchedulingDecision decision) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${decision.hardViolations.first} Suggested time: '
          '${_formatSuggestedTime(decision.scheduledAt)}',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.errorRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatSuggestedTime(DateTime dateTime) {
    final hour = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour < 12 ? 'AM' : 'PM';
    return '${dateTime.month}/${dateTime.day} $hour:$minute $suffix';
  }

  String _repeatTypeFromMinutes() {
    if (_repeatIntervalMinutes == 43200) return 'monthly';
    if (_repeatIntervalMinutes == 10080) return 'weekly';
    if (_repeatIntervalMinutes == 1440) return 'daily';
    return 'custom:$_repeatIntervalMinutes';
  }

  int _repeatMinutesFromType(String? repeatType) {
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

  DateTime? _dateTimeFromValue(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;

      final millis = int.tryParse(value);
      if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  double? _doubleFrom(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _useCurrentLocation() async {
    final location = await LocationReminderService.instance.currentLocation();
    if (!mounted) return;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get current location')),
      );
      return;
    }

    setState(() {
      _locationLatitude = location.latitude;
      _locationLongitude = location.longitude;
      if (_locationNameController.text.trim().isEmpty) {
        _locationNameController.text = 'Current location';
      }
      _timeError = null;
    });
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: AppTheme.primaryBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _hasChangedSchedule = true;
        if (_timeError != null && !_isTimeInPast()) _timeError = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: AppTheme.primaryBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _hasChangedSchedule = true;
        if (_timeError != null && !_isTimeInPast()) _timeError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(theme),
      body: SafeArea(
        child: FadeTransition(
          opacity: _formFade,
          child: SlideTransition(
            position: _formSlide,
            child: isTablet
                ? _buildTabletLayout(theme)
                : _buildPhoneLayout(theme),
          ),
        ),
      ),
      floatingActionButton: EmergencyFabWidget(
        contacts: _emergencyContacts,
        countdownEnabled: false,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: theme.colorScheme.outline.withAlpha(51),
      leading: IconButton(
        icon: CustomIconWidget(
          iconName: 'arrow_back',
          color: theme.colorScheme.onSurface,
          size: 24,
        ),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Cancel',
      ),
      title: Text(
        _isEditing ? 'Edit $_reminderLabel' : 'Add $_reminderLabel',
        style: GoogleFonts.nunitoSans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunitoSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneLayout(ThemeData theme) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 96),
        children: [
          _buildTitleSection(theme),
          const SizedBox(height: 16),
          _buildDescriptionSection(theme),
          const SizedBox(height: 16),
          _buildDateTimeSection(theme),
          const SizedBox(height: 16),
          _buildCategorySection(theme),
          const SizedBox(height: 16),
          _buildRepeatSection(theme),
          const SizedBox(height: 20),
          _buildLocationSection(theme),
          const SizedBox(height: 20),
          _buildSaveButton(theme),
          const SizedBox(height: 10),
          _buildCancelButton(theme),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(ThemeData theme) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Form(
      key: _formKey,
      child: Center(
        child: SizedBox(
          width: 680,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(0, 16, 0, bottomInset + 96),
            children: [
              // Two-column layout for short fields
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildTitleSection(theme)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildDescriptionSection(theme)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: _buildDateTimeSection(theme))],
              ),
              const SizedBox(height: 16),
              _buildCategorySection(theme),
              const SizedBox(height: 16),
              _buildRepeatSection(theme),
              const SizedBox(height: 20),
              _buildLocationSection(theme),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildCancelButton(theme)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildSaveButton(theme)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleSection(ThemeData theme) {
    return FormSectionCardWidget(
      title: '$_reminderLabel Title',
      isRequired: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
            style: GoogleFonts.nunitoSans(
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'What do you need to remember?',
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CustomIconWidget(
                  iconName: 'alarm',
                  color: theme.colorScheme.outline,
                  size: 22,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              errorText: _titleError,
              errorStyle: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: AppTheme.errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(ThemeData theme) {
    return FormSectionCardWidget(
      title: '$_noteLabel (Optional)',
      child: TextFormField(
        controller: _descriptionController,
        maxLines: 3,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
        style: GoogleFonts.nunitoSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          hintText: 'Add a note...',
          alignLabelWithHint: true,
          prefixIcon: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: CustomIconWidget(
              iconName: 'edit',
              color: theme.colorScheme.outline,
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 48),
        ),
      ),
    );
  }

  Widget _buildDateTimeSection(ThemeData theme) {
    return FormSectionCardWidget(
      title: 'Date & Time',
      isRequired: true,
      child: Column(
        children: [
          DateTimePickerWidget(
            selectedDate: _selectedDate,
            selectedTime: _selectedTime,
            onDateTap: _pickDate,
            onTimeTap: _pickTime,
          ),
          if (_timeError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 4),
                CustomIconWidget(
                  iconName: 'error',
                  color: AppTheme.errorRed,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _timeError!,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: AppTheme.errorRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategorySection(ThemeData theme) {
    return FormSectionCardWidget(
      title: 'Category',
      child: CategoryChipRowWidget(
        selectedCategory: _selectedCategory,
        onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
      ),
    );
  }

  Widget _buildRepeatSection(ThemeData theme) {
    return FormSectionCardWidget(
      title: 'Frequency',
      child: RepeatSettingsWidget(
        isRepeating: _isRepeating,
        repeatIntervalMinutes: _repeatIntervalMinutes,
        onRepeatingChanged: (v) => setState(() => _isRepeating = v),
        onIntervalChanged: (v) => setState(() => _repeatIntervalMinutes = v),
      ),
    );
  }

  Widget _buildLocationSection(ThemeData theme) {
    final hasCoordinates =
        _locationLatitude != null && _locationLongitude != null;
    return FormSectionCardWidget(
      title: 'Location Reminder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Trigger by location',
              style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Arrive at or leave a saved place',
              style: GoogleFonts.nunitoSans(fontSize: 13),
            ),
            value: _locationEnabled,
            onChanged: (value) => setState(() => _locationEnabled = value),
          ),
          if (_locationEnabled) ...[
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'arrive',
                  icon: Icon(Icons.login),
                  label: Text('Arrive'),
                ),
                ButtonSegment(
                  value: 'leave',
                  icon: Icon(Icons.logout),
                  label: Text('Leave'),
                ),
              ],
              selected: {_locationTrigger},
              onSelectionChanged: (value) {
                setState(() => _locationTrigger = value.first);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Place name, e.g. Mercury Drug',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _useCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: Text(
                hasCoordinates
                    ? 'Update Current Location'
                    : 'Use Current Location',
              ),
            ),
            if (hasCoordinates) ...[
              const SizedBox(height: 8),
              Text(
                'Saved near ${_locationLatitude!.toStringAsFixed(5)}, '
                '${_locationLongitude!.toStringAsFixed(5)}',
                style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton(ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveReminder,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 3,
          shadowColor: AppTheme.primaryBlue.withAlpha(102),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 24,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isEditing
                        ? 'Update $_reminderLabel'
                        : 'Save $_reminderLabel',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCancelButton(ThemeData theme) {
    return OutlinedButton(
      onPressed: _isSaving ? null : () => Navigator.pop(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.outline,
        side: BorderSide(color: theme.colorScheme.outlineVariant, width: 1.5),
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        'Cancel',
        style: GoogleFonts.nunitoSans(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}
