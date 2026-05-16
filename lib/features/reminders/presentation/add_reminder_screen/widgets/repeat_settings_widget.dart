import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lifeease/core/services/tts/tts_language_service.dart';
import 'package:lifeease/core/themes/app_theme.dart';
import 'package:lifeease/shared/widgets/custom_icon_widget.dart';

class _RepeatInterval {
  final int minutes;
  final String englishLabel;
  final String tagalogLabel;

  const _RepeatInterval(this.minutes, this.englishLabel, this.tagalogLabel);
}

class _FrequencyOption {
  final String id;
  final int minutes;
  final bool repeats;
  final String englishLabel;
  final String tagalogLabel;

  const _FrequencyOption({
    required this.id,
    required this.minutes,
    required this.repeats,
    required this.englishLabel,
    required this.tagalogLabel,
  });
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

  static const _frequencies = [
    _FrequencyOption(
      id: 'once',
      minutes: 0,
      repeats: false,
      englishLabel: 'One time only',
      tagalogLabel: 'Isang beses lang',
    ),
    _FrequencyOption(
      id: 'daily',
      minutes: 1440,
      repeats: true,
      englishLabel: 'Every day',
      tagalogLabel: 'Araw-araw',
    ),
    _FrequencyOption(
      id: 'morning_evening',
      minutes: 720,
      repeats: true,
      englishLabel: 'Morning and evening',
      tagalogLabel: 'Umaga at gabi',
    ),
    _FrequencyOption(
      id: 'weekly',
      minutes: 10080,
      repeats: true,
      englishLabel: 'Every week',
      tagalogLabel: 'Linggo-linggo',
    ),
    _FrequencyOption(
      id: 'monthly',
      minutes: 43200,
      repeats: true,
      englishLabel: 'Every month',
      tagalogLabel: 'Buwan-buwan',
    ),
    _FrequencyOption(
      id: 'twice_monthly',
      minutes: 21600,
      repeats: true,
      englishLabel: 'Twice a month',
      tagalogLabel: 'Dalawang beses sa isang buwan',
    ),
    _FrequencyOption(
      id: 'custom',
      minutes: 60,
      repeats: true,
      englishLabel: 'Custom',
      tagalogLabel: 'Sarili mong iskedyul',
    ),
  ];

  static const _customIntervals = [
    _RepeatInterval(15, 'Very often', 'Madalas na madalas'),
    _RepeatInterval(30, 'Often', 'Madalas'),
    _RepeatInterval(60, 'About every hour', 'Halos bawat oras'),
    _RepeatInterval(120, 'Every two hours', 'Kada dalawang oras'),
    _RepeatInterval(240, 'Every four hours', 'Kada apat na oras'),
    _RepeatInterval(360, 'Every six hours', 'Kada anim na oras'),
    _RepeatInterval(480, 'Three times a day', 'Tatlong beses sa isang araw'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTagalog =
        TtsLanguageService.currentLanguage == AppSpeechLanguage.tagalog;
    final selectedFrequencyId = _selectedFrequencyId;
    final showCustom = selectedFrequencyId == 'custom';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    isTagalog
                        ? 'Gaano kadalas kang papaalalahanan ng LifeEase?'
                        : 'How often should LifeEase remind you?',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    isTagalog
                        ? 'Pumili ng malinaw na iskedyul para sa paalala.'
                        : 'Choose a simple schedule for this reminder.',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildDropdown<String>(
          theme: theme,
          value: selectedFrequencyId,
          items: _frequencies.map((option) {
            return DropdownMenuItem<String>(
              value: option.id,
              child: Text(_optionLabel(option, isTagalog)),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            final option = _frequencies.firstWhere((item) => item.id == value);
            onRepeatingChanged(option.repeats);
            onIntervalChanged(option.minutes);
          },
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: showCustom
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildDropdown<int>(
              theme: theme,
              value: _customIntervalValue,
              items: _customIntervals.map((interval) {
                return DropdownMenuItem<int>(
                  value: interval.minutes,
                  child: Text(
                    isTagalog ? interval.tagalogLabel : interval.englishLabel,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) onIntervalChanged(value);
              },
            ),
          ),
        ),
      ],
    );
  }

  String get _selectedFrequencyId {
    if (!isRepeating) return 'once';
    for (final option in _frequencies) {
      if (option.id != 'custom' && option.minutes == repeatIntervalMinutes) {
        return option.id;
      }
    }
    return 'custom';
  }

  int get _customIntervalValue {
    for (final interval in _customIntervals) {
      if (interval.minutes == repeatIntervalMinutes) return interval.minutes;
    }
    return _customIntervals.first.minutes;
  }

  String _optionLabel(_FrequencyOption option, bool isTagalog) {
    return isTagalog ? option.tagalogLabel : option.englishLabel;
  }

  Widget _buildDropdown<T>({
    required ThemeData theme,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
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
          onChanged: onChanged,
          items: items,
        ),
      ),
    );
  }
}
