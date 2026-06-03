/// Parsed clock time from spoken reminder phrases.
class VoiceTimeOfDay {
  const VoiceTimeOfDay({required this.hour, required this.minute});

  final int hour;
  final int minute;
}

/// Shared time extraction for voice reminders (command parser, assistant, guided flow).
class VoiceTimeParser {
  const VoiceTimeParser._();

  static VoiceTimeOfDay? parse(String text) {
    final normalized = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    // Hour + minute with AM/PM (requires :, ., or space between hour and minute).
    var match = RegExp(
      r'(\d{1,2})(?:\s*[:.]\s*|\s+)(\d{1,2})\s*[:.\s]?\s*(am|pm|a\.m\.?|p\.m\.?)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match != null) {
      final parsed = _from12Hour(
        int.tryParse(match.group(1) ?? ''),
        int.tryParse(match.group(2) ?? '0'),
        match.group(3),
      );
      if (parsed != null) return parsed;
    }

    // Hour only with AM/PM (e.g. "10pm", "3 AM").
    match = RegExp(
      r'(\d{1,2})\s*(?:o?clock)?\s*[:.\s]?\s*(am|pm|a\.m\.?|p\.m\.?)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match != null) {
      final parsed = _from12Hour(
        int.tryParse(match.group(1) ?? ''),
        0,
        match.group(2),
      );
      if (parsed != null) return parsed;
    }

    // 24-hour format (15:30, 23:45).
    match = RegExp(r'(\d{1,2})\s*[:.]\s*(\d{1,2})').firstMatch(normalized);
    if (match != null) {
      final hour = int.tryParse(match.group(1) ?? '');
      final minute = int.tryParse(match.group(2) ?? '0');
      if (hour != null &&
          minute != null &&
          hour > 12 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        return VoiceTimeOfDay(hour: hour, minute: minute);
      }
    }

    if (normalized.contains('noon')) {
      return const VoiceTimeOfDay(hour: 12, minute: 0);
    }
    if (normalized.contains('midnight')) {
      return const VoiceTimeOfDay(hour: 0, minute: 0);
    }
    if (normalized.contains('morning') || normalized.contains('umaga')) {
      return const VoiceTimeOfDay(hour: 8, minute: 0);
    }
    if (normalized.contains('evening') || normalized.contains('gabi')) {
      return const VoiceTimeOfDay(hour: 18, minute: 0);
    }

    return null;
  }

  static bool hasExplicitTime(String text) {
    if (parse(text) != null) return true;
    final normalized = text.trim().toLowerCase();
    return normalized.contains('morning') ||
        normalized.contains('evening') ||
        normalized.contains('umaga') ||
        normalized.contains('gabi') ||
        normalized.contains('noon') ||
        normalized.contains('midnight');
  }

  static VoiceTimeOfDay? _from12Hour(int? hour, int? minute, String? suffixRaw) {
    if (hour == null || minute == null) return null;
    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;

    final suffix = (suffixRaw ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'\.'), '')
        .trim();
    if (!suffix.startsWith('a') && !suffix.startsWith('p')) return null;

    var h = hour;
    if (suffix.startsWith('p') && h < 12) h += 12;
    if (suffix.startsWith('a') && h == 12) h = 0;

    return VoiceTimeOfDay(hour: h.clamp(0, 23), minute: minute.clamp(0, 59));
  }
}
