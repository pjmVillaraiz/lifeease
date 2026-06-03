class ParsedReminderDraft {
  const ParsedReminderDraft({
    required this.title,
    required this.note,
    required this.scheduledAt,
    required this.frequency,
    required this.repeatType,
    required this.repeatIntervalMinutes,
    required this.frequencyLabel,
    required this.originalText,
    required this.hasExplicitDate,
    required this.hasExplicitTime,
  });

  final String title;
  final String note;
  final DateTime scheduledAt;
  final String frequency;
  final String repeatType;
  final int repeatIntervalMinutes;
  final String frequencyLabel;
  final String originalText;
  final bool hasExplicitDate;
  final bool hasExplicitTime;

  bool get isRepeating => repeatType != 'none';
}

class ReminderParser {
  ReminderParser({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  ParsedReminderDraft? parse(String rawText) {
    final original = rawText.trim();
    final normalized = _normalize(original);
    if (normalized.isEmpty || !_looksLikeReminder(normalized)) return null;

    final now = _now();
    final dateResult = _extractDate(normalized, now);
    final timeResult = _extractTime(normalized);
    final frequency = _extractFrequency(normalized);
    final note = _extractNote(original);
    final title = _extractTitle(original);
    if (title.isEmpty) return null;

    final fallback = now.add(const Duration(hours: 1));
    final selectedDate = dateResult.date;
    final selectedTime =
        timeResult ?? _TimeParts(fallback.hour, fallback.minute);
    var scheduledAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (!scheduledAt.isAfter(now)) {
      scheduledAt = scheduledAt.add(const Duration(days: 1));
    }

    return ParsedReminderDraft(
      title: _capitalize(title),
      note: note,
      scheduledAt: scheduledAt,
      frequency: frequency.key,
      repeatType: frequency.repeatType,
      repeatIntervalMinutes: frequency.repeatIntervalMinutes,
      frequencyLabel: frequency.label,
      originalText: original,
      hasExplicitDate: dateResult.isExplicit,
      hasExplicitTime: timeResult != null,
    );
  }

  bool _looksLikeReminder(String text) {
    return _hasAny(text, const [
      'remind me',
      'add reminder',
      'add a reminder',
      'create reminder',
      'set reminder',
      'set a reminder',
      'paalalahanan mo ako',
      'paalalahanan',
      'magdagdag ng paalala',
      'paalala ako',
      'reminder ako',
      'mag remind',
      'mag-remind',
    ]);
  }

  _DateResult _extractDate(String text, DateTime now) {
    if (_hasAny(text, const ['tomorrow', 'bukas'])) {
      final tomorrow = now.add(const Duration(days: 1));
      return _DateResult(
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
        true,
      );
    }

    if (_hasAny(text, const ['today', 'ngayon'])) {
      return _DateResult(DateTime(now.year, now.month, now.day), true);
    }

    return _DateResult(DateTime(now.year, now.month, now.day), false);
  }

  _TimeParts? _extractTime(String text) {
    final match = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    ).firstMatch(text);
    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '') ?? 0;
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    final suffix = (match.group(3) ?? '').toLowerCase();
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    return _TimeParts(hour.clamp(0, 23), minute.clamp(0, 59));
  }

  _Frequency _extractFrequency(String text) {
    final customHours = _customHourlyInterval(text);
    if (customHours != null) {
      final minutes = customHours * 60;
      return _Frequency(
        'custom_${customHours}_hours',
        'custom:$minutes',
        minutes,
        'Every $customHours ${customHours == 1 ? 'hour' : 'hours'}',
      );
    }
    if (_hasAny(text, const ['morning and evening', 'umaga at gabi'])) {
      return const _Frequency(
        'morning_evening',
        'custom:720',
        720,
        'Morning and evening',
      );
    }
    if (_hasAny(text, const [
      'twice a week',
      'two times a week',
      'dalawang beses kada linggo',
    ])) {
      return const _Frequency(
        'twice_weekly',
        'custom:5040',
        5040,
        'Twice a week',
      );
    }
    if (_hasAny(text, const [
      'twice a month',
      'two times a month',
      'dalawang beses kada buwan',
    ])) {
      return const _Frequency(
        'twice_monthly',
        'twice_monthly',
        21600,
        'Twice a month',
      );
    }
    if (_hasAny(text, const ['every hour', 'hourly', 'kada oras'])) {
      return const _Frequency('every_hour', 'custom:60', 60, 'Every hour');
    }
    if (_hasAny(text, const ['every day', 'daily', 'araw-araw'])) {
      return const _Frequency('daily', 'daily', 1440, 'Every day');
    }
    if (_hasAny(text, const ['every week', 'weekly', 'linggo-linggo'])) {
      return const _Frequency('weekly', 'weekly', 10080, 'Every week');
    }
    if (_hasAny(text, const ['every month', 'monthly', 'buwan-buwan'])) {
      return const _Frequency('monthly', 'monthly', 43200, 'Every month');
    }
    return const _Frequency('none', 'none', 0, 'One time only');
  }

  int? _customHourlyInterval(String text) {
    final match = RegExp(
      r'\b(?:every|kada)\s+(\d{1,2})\s+(?:hour|hours|oras)\b',
    ).firstMatch(text);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '');
    if (hours == null || hours < 1 || hours > 10) return null;
    return hours;
  }

  String _extractNote(String rawText) {
    final match = RegExp(
      r'\b(?:note|notes|tala)\s+(.+?)(?:\s+today\b|\s+tomorrow\b|\s+ngayon\b|\s+bukas\b|\s+at\s+\d{1,2}|\s+ng\s+\d{1,2}|\s+oras\s+\d{1,2}|\s+every\b|\s+araw-araw\b|\s+kada oras\b|\s+linggo-linggo\b|\s+buwan-buwan\b|$)',
      caseSensitive: false,
    ).firstMatch(rawText);
    return match?.group(1)?.trim() ?? '';
  }

  String _extractTitle(String rawText) {
    var title = rawText.trim();
    final cleanupPatterns = [
      r'^\s*(please\s+)?',
      r'^\s*(remind me to|remind me|add reminder to|add reminder|add a reminder to|add a reminder|create reminder to|create reminder|set a reminder to|set a reminder|set reminder to|set reminder)\s+',
      r'^\s*(paalalahanan mo ako na|paalalahanan mo ako|paalalahanan ako na|paalalahanan ako|magdagdag ng paalala na|magdagdag ng paalala|paalala ako na|paalala ako|reminder ako na|reminder ako|mag-?\s*remind ako na|mag-?\s*remind ako|mag-?\s*remind)\s+',
      r'\b(?:note|notes|tala)\s+.+$',
      r'\b(?:today|tomorrow|ngayon|bukas)\b',
      r'\b(?:at|ng|oras)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)\b',
      r'\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b',
      r'\b(?:every hour|hourly|kada oras)\b',
      r'\b(?:every|kada)\s+\d{1,2}\s+(?:hour|hours|oras)\b',
      r'\b(?:every day|daily|araw-araw)\b',
      r'\b(?:morning and evening|umaga at gabi)\b',
      r'\b(?:every week|weekly|linggo-linggo)\b',
      r'\b(?:twice a week|two times a week|dalawang beses kada linggo)\b',
      r'\b(?:every month|monthly|buwan-buwan)\b',
      r'\b(?:twice a month|two times a month|dalawang beses kada buwan)\b',
    ];

    for (final pattern in cleanupPatterns) {
      title = title.replaceAll(RegExp(pattern, caseSensitive: false), ' ');
    }

    title = title
        .replaceAll(RegExp(r'^\s*(to|na)\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return title;
  }

  bool _hasAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

class _DateResult {
  const _DateResult(this.date, this.isExplicit);

  final DateTime date;
  final bool isExplicit;
}

class _TimeParts {
  const _TimeParts(this.hour, this.minute);

  final int hour;
  final int minute;
}

class _Frequency {
  const _Frequency(
    this.key,
    this.repeatType,
    this.repeatIntervalMinutes,
    this.label,
  );

  final String key;
  final String repeatType;
  final int repeatIntervalMinutes;
  final String label;
}
