import 'package:lifeease/models/parsed_command.dart';

class RuleBasedCommandParser {
  ParsedCommand parse(String normalizedText) {
    final text = normalizedText.toLowerCase().trim();

    String intent = 'unknown';
    String? task;
    String? date;
    String? time;

    // 1. Determine Intent
    if (text.contains('call emergency') ||
        text.contains('emergency call') ||
        text.contains('dial emergency') ||
        text.contains('call help') ||
        text.contains('call 911') ||
        text.contains('call 912') ||
        text.contains('call family') ||
        text.contains('emergency contact')) {
      intent = 'emergency_call';
    } else if (text.contains('send emergency message') ||
        text.contains('emergency message') ||
        text.contains('text emergency') ||
        text.contains('message emergency') ||
        text.contains('send alert') ||
        text.contains('emergency text')) {
      intent = 'emergency_message';
    } else if (text.contains('open settings') ||
        text.contains('go to settings') ||
        text.contains('show settings') ||
        text.contains('settings screen')) {
      intent = 'open_settings';
    } else if (text.contains('show reminders') ||
        text.contains('list reminders') ||
        text.contains('view reminders') ||
        text.contains('what are my reminders') ||
        text.contains('show my reminders') ||
        text.contains('my reminders')) {
      intent = 'show_reminders';
    } else if (text.contains('remind me') ||
        text.contains('add reminder') ||
        text.contains('create reminder') ||
        text.contains('set reminder') ||
        text.contains('remind')) {
      intent = 'create_reminder';
    } else {
      // Default to create_reminder if there are time or date words
      if (text.contains(' at ') ||
          text.contains(' pm') ||
          text.contains(' am') ||
          text.contains('tomorrow') ||
          text.contains('today')) {
        intent = 'create_reminder';
      }
    }

    // 2. Extract Fields for Reminders
    if (intent == 'create_reminder') {
      // Extract Date
      if (text.contains('tomorrow')) {
        date = 'tomorrow';
      } else {
        date = 'today';
      }

      // Extract Time
      final timeMatch = RegExp(
        r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (timeMatch != null) {
        final hour = timeMatch.group(1)!;
        final minute = timeMatch.group(2) ?? '00';
        final ampm = timeMatch.group(3)!.toUpperCase();
        time = '$hour:${minute.padLeft(2, '0')} $ampm';
      }

      // Extract Task
      var cleanedTask = normalizedText;

      final prefixes = [
        RegExp(r'^remind me to\s+', caseSensitive: false),
        RegExp(r'^remind me\s+', caseSensitive: false),
        RegExp(r'^add reminder to\s+', caseSensitive: false),
        RegExp(r'^add reminder\s+', caseSensitive: false),
        RegExp(r'^create reminder to\s+', caseSensitive: false),
        RegExp(r'^create reminder\s+', caseSensitive: false),
        RegExp(r'^set reminder to\s+', caseSensitive: false),
        RegExp(r'^set reminder\s+', caseSensitive: false),
        RegExp(r'^remind\s+', caseSensitive: false),
      ];

      for (final pattern in prefixes) {
        cleanedTask = cleanedTask.replaceFirst(pattern, '');
      }

      final suffixes = [
        RegExp(r'\s+at\s+\d{1,2}(?::\d{2})?\s*(am|pm)\b', caseSensitive: false),
        RegExp(r'\s+at\s+\d{1,2}\s*(am|pm)\b', caseSensitive: false),
        RegExp(r'\b\d{1,2}(?::\d{2})?\s*(am|pm)\b', caseSensitive: false),
        RegExp(r'\b\d{1,2}\s*(am|pm)\b', caseSensitive: false),
        RegExp(r'\s+tomorrow\b', caseSensitive: false),
        RegExp(r'\s+today\b', caseSensitive: false),
        RegExp(r'\btomorrow\b', caseSensitive: false),
        RegExp(r'\btoday\b', caseSensitive: false),
      ];

      for (final pattern in suffixes) {
        cleanedTask = cleanedTask.replaceAll(pattern, '');
      }

      cleanedTask = cleanedTask.trim();
      if (cleanedTask.isNotEmpty) {
        task = cleanedTask;
      }
    }

    return ParsedCommand(
      intent: intent,
      task: task,
      date: date,
      time: time,
    );
  }
}
