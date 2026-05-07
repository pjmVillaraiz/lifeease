import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum BadgeStatus { pending, completed, overdue, warning, info }

class StatusBadgeWidget extends StatelessWidget {
  final BadgeStatus status;
  final String label;
  final bool compact;

  const StatusBadgeWidget({
    super.key,
    required this.status,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _colorsForStatus();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunitoSans(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: colors.$2,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  (Color, Color) _colorsForStatus() {
    switch (status) {
      case BadgeStatus.pending:
        return (AppTheme.primaryContainer, AppTheme.primaryBlue);
      case BadgeStatus.completed:
        return (AppTheme.successContainer, AppTheme.success);
      case BadgeStatus.overdue:
        return (AppTheme.errorContainer, AppTheme.errorRed);
      case BadgeStatus.warning:
        return (AppTheme.warningContainer, AppTheme.warning);
      case BadgeStatus.info:
        return (AppTheme.secondaryContainer, AppTheme.secondaryTeal);
    }
  }
}
