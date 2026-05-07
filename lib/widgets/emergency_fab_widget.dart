import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class EmergencyContact {
  final int? id;
  final String name;
  final String phone;
  final String relationship;
  final int priority;

  const EmergencyContact({
    this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.priority,
  });
}

class EmergencyFabWidget extends StatefulWidget {
  final List<EmergencyContact> contacts;
  final bool countdownEnabled;
  final int countdownSeconds;

  const EmergencyFabWidget({
    super.key,
    required this.contacts,
    this.countdownEnabled = false,
    this.countdownSeconds = 3,
  });

  @override
  State<EmergencyFabWidget> createState() => _EmergencyFabWidgetState();
}

class _EmergencyFabWidgetState extends State<EmergencyFabWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleFabTap() {
    HapticFeedback.heavyImpact();
    if (widget.contacts.isEmpty) {
      _showNoContactsDialog();
      return;
    }
    _showContactsBottomSheet();
  }

  void _showNoContactsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppTheme.primaryBlue),
            const SizedBox(width: 8),
            Text(
              'No Contacts Set',
              style: GoogleFonts.nunitoSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Add an emergency contact in Settings first.',
          style: GoogleFonts.nunitoSans(fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.nunitoSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContactsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ContactsBottomSheet(
        contacts: widget.contacts,
        countdownEnabled: widget.countdownEnabled,
        countdownSeconds: widget.countdownSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) =>
          Transform.scale(scale: _pulseAnimation.value, child: child),
      child: FloatingActionButton.extended(
        onPressed: _handleFabTap,
        backgroundColor: AppTheme.errorRed,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.phone_rounded, size: 22),
        label: Text(
          'Call Family',
          style: GoogleFonts.nunitoSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _ContactsBottomSheet extends StatefulWidget {
  final List<EmergencyContact> contacts;
  final bool countdownEnabled;
  final int countdownSeconds;

  const _ContactsBottomSheet({
    required this.contacts,
    required this.countdownEnabled,
    required this.countdownSeconds,
  });

  @override
  State<_ContactsBottomSheet> createState() => _ContactsBottomSheetState();
}

class _ContactsBottomSheetState extends State<_ContactsBottomSheet> {
  String? _countingDownPhone;
  String? _countingDownName;
  int _secondsLeft = 0;
  bool _calling = false;

  void _startCountdown(EmergencyContact contact) {
    setState(() {
      _countingDownPhone = contact.phone;
      _countingDownName = contact.name;
      _secondsLeft = widget.countdownSeconds;
      _calling = true;
    });
    _tick();
  }

  void _tick() {
    if (!mounted || !_calling) return;
    if (_secondsLeft <= 0) {
      _executeCall(_countingDownPhone!);
      return;
    }
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_calling) return;
      setState(() => _secondsLeft--);
      _tick();
    });
  }

  void _cancelCountdown() {
    setState(() {
      _countingDownPhone = null;
      _countingDownName = null;
      _secondsLeft = 0;
      _calling = false;
    });
  }

  void _executeCall(String phone) {
    // TODO: Replace with url_launcher — launch('tel:$phone')
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Calling $phone...',
            style: GoogleFonts.nunitoSans(fontSize: 15),
          ),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.phone_rounded,
                      color: AppTheme.errorRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Emergency Contacts',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_calling)
              _buildCountdownBanner()
            else
              ...widget.contacts.map((c) => _buildContactTile(c, theme)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              'Calling $_countingDownName in $_secondsLeft seconds...',
              style: GoogleFonts.nunitoSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.errorRed,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _cancelCountdown,
              icon: const Icon(Icons.close_rounded, color: AppTheme.errorRed),
              label: Text(
                'Cancel',
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.errorRed,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.errorRed, width: 1.5),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile(EmergencyContact contact, ThemeData theme) {
    final priorityLabels = {1: 'Primary', 2: 'Secondary', 3: 'Tertiary'};
    final priorityColors = {
      1: AppTheme.errorRed,
      2: AppTheme.warning,
      3: AppTheme.secondaryTeal,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color:
                  (priorityColors[contact.priority] ?? AppTheme.categoryGeneral)
                      .withAlpha(38),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color:
                      priorityColors[contact.priority] ??
                      AppTheme.categoryGeneral,
                ),
              ),
            ),
          ),
          title: Text(
            contact.name,
            style: GoogleFonts.nunitoSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contact.phone,
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      (priorityColors[contact.priority] ??
                              AppTheme.categoryGeneral)
                          .withAlpha(31),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${priorityLabels[contact.priority] ?? 'Contact'} · ${contact.relationship}',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        priorityColors[contact.priority] ??
                        AppTheme.categoryGeneral,
                  ),
                ),
              ),
            ],
          ),
          trailing: ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              if (widget.countdownEnabled) {
                _startCountdown(contact);
              } else {
                _executeCall(contact.phone);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(90, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              'Call Now',
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
