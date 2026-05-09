import 'package:flutter/services.dart';

import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/features/scheduling/domain/rule_based_scheduling_engine.dart';
import 'package:lifeease/shared/widgets/emergency_fab_widget.dart';
import './widgets/category_chip_row_widget.dart';
import './widgets/date_time_picker_widget.dart';
import './widgets/form_section_card_widget.dart';
import './widgets/repeat_settings_widget.dart';

class AddReminderScreen extends StatefulWidget {
  final int? prefillHour;
  final String? prefillTitle;
  final TimeOfDay? prefillTime;

  const AddReminderScreen({
    super.key,
    this.prefillHour,
    this.prefillTitle,
    this.prefillTime,
  });

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _selectedCategory = 'general';
  bool _isRepeating = false;
  int _repeatIntervalMinutes = 60;
  bool _isSaving = false;
  final ReminderRepository _reminderRepository = ReminderRepository();
  final RuleBasedSchedulingEngine _schedulingEngine =
      RuleBasedSchedulingEngine();

  String? _titleError;
  String? _timeError;

  late AnimationController _entranceController;
  late Animation<double> _formFade;
  late Animation<Offset> _formSlide;

  final List<EmergencyContact> _emergencyContacts = const [
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

    _selectedDate = DateTime.now();
    _selectedTime =
        widget.prefillTime ??
        (widget.prefillHour != null
            ? TimeOfDay(hour: widget.prefillHour!, minute: 0)
            : TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: 0));

    if (widget.prefillTitle != null) {
      _titleController.text = widget.prefillTitle!;
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
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
    if (_isTimeInPast()) {
      setState(() => _timeError = 'Scheduled time cannot be in the past');
      valid = false;
    }
    if (!valid) {
      HapticFeedback.lightImpact();
      return;
    }

    final scheduled = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
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
      const [],
    );

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();
    final localId = DateTime.now().millisecondsSinceEpoch.toString();

    await _reminderRepository.saveReminder({
      'id': localId,
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'reminder_time': decision.scheduledAt.toIso8601String(),
      'scheduledTimeMillis': decision.scheduledAt.millisecondsSinceEpoch,
      'category': _selectedCategory,
      'repeat_type': _isRepeating ? _repeatTypeFromMinutes() : 'none',
      'isRepeating': _isRepeating,
      'repeatIntervalMinutes': _isRepeating ? _repeatIntervalMinutes : 0,
      'priority': decision.priority.name,
      'is_completed': false,
      'isCompleted': false,
      'sync_status': 'queued',
      'created_at': DateTime.now().toIso8601String(),
    });

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
                  ? 'Reminder saved'
                  : 'Reminder saved with scheduling suggestion',
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

    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.homeScreen,
      (route) => false,
    );
  }

  String _repeatTypeFromMinutes() {
    if (_repeatIntervalMinutes >= 43200) return 'monthly';
    if (_repeatIntervalMinutes >= 10080) return 'weekly';
    if (_repeatIntervalMinutes >= 1440) return 'daily';
    return 'custom';
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
        'Add Reminder',
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
      title: 'Reminder Title',
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
      title: 'Notes (Optional)',
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
          hintText: 'Add additional details...',
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
      title: 'Repeat',
      child: RepeatSettingsWidget(
        isRepeating: _isRepeating,
        repeatIntervalMinutes: _repeatIntervalMinutes,
        onRepeatingChanged: (v) => setState(() => _isRepeating = v),
        onIntervalChanged: (v) => setState(() => _repeatIntervalMinutes = v),
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
                    'Save Reminder',
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
