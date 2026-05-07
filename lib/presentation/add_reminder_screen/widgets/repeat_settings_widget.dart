import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_icon_widget.dart';

class _RepeatInterval {
  final int minutes;
  final String label;

  const _RepeatInterval(this.minutes, this.label);
}

class RepeatSettingsWidget extends StatelessWidget {
  final bool isRepeating;
  final int repeatIntervalMinutes;
  final ValueChanged<bool> onRepeatingChanged;
  final ValueChanged<int> onIntervalChanged;

  const RepeatSettingsWidget({
    super.key,
    required this.isRepeating,
    required this.repeatIntervalMinutes,
    required this.onRepeatingChanged,
    required this.onIntervalChanged,
  });

  static const _intervals = [
    _RepeatInterval(15, 'Every 15 minutes'),
    _RepeatInterval(30, 'Every 30 minutes'),
    _RepeatInterval(60, 'Every hour'),
    _RepeatInterval(120, 'Every 2 hours'),
    _RepeatInterval(1440, 'Daily'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Repeat toggle row
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isRepeating
                    ? AppTheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: CustomIconWidget(
                iconName: 'repeat',
                color: isRepeating
                    ? AppTheme.primaryBlue
                    : theme.colorScheme.outline,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repeat Reminder',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Automatically reschedule after each alert',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: isRepeating,
              onChanged: onRepeatingChanged,
              activeThumbColor: AppTheme.primaryBlue,
            ),
          ],
        ),
        // Interval selector (visible when repeating is ON)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: isRepeating
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Repeat Every',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: repeatIntervalMinutes,
                      isExpanded: true,
                      icon: CustomIconWidget(
                        iconName: 'expand_more',
                        color: theme.colorScheme.outline,
                        size: 22,
                      ),
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      dropdownColor: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      onChanged: (v) {
                        if (v != null) onIntervalChanged(v);
                      },
                      items: _intervals.map((interval) {
                        return DropdownMenuItem<int>(
                          value: interval.minutes,
                          child: Text(
                            interval.label,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
