import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import 'package:lifeease/core/services/tts/tts_language_service.dart';

enum AssistantIntent { createReminder, reminderQuery, internetQuery, unknown }

enum ReminderQueryType { today, next, medicineNow, pendingCount }

class VoiceReminderDraft {
  const VoiceReminderDraft({
    required this.title,
    required this.note,
    required this.scheduledAt,
    required this.repeatType,
    required this.repeatIntervalMinutes,
    required this.frequencyLabel,
    required this.originalText,
  });

  final String title;
  final String note;
  final DateTime scheduledAt;
  final String repeatType;
  final int repeatIntervalMinutes;
  final String frequencyLabel;
  final String originalText;

  bool get isRepeating => repeatType != 'none';
}

class AssistantResult {
  const AssistantResult({
    required this.intent,
    this.reminderDraft,
    this.reminderQueryType,
    this.answer,
  });

  final AssistantIntent intent;
  final VoiceReminderDraft? reminderDraft;
  final ReminderQueryType? reminderQueryType;
  final String? answer;
}

class VoiceAssistantService {
  const VoiceAssistantService();

  Future<AssistantResult> handle(String rawText) async {
    final normalized = _normalize(rawText);
    if (normalized.isEmpty) {
      return const AssistantResult(intent: AssistantIntent.unknown);
    }

    final reminderDraft = parseReminder(rawText);
    if (reminderDraft != null) {
      return AssistantResult(
        intent: AssistantIntent.createReminder,
        reminderDraft: reminderDraft,
      );
    }

    final reminderQueryType = _reminderQueryType(normalized);
    if (reminderQueryType != null) {
      return AssistantResult(
        intent: AssistantIntent.reminderQuery,
        reminderQueryType: reminderQueryType,
      );
    }

    if (_isInternetQuery(normalized)) {
      return AssistantResult(
        intent: AssistantIntent.internetQuery,
        answer: await answerOnline(rawText),
      );
    }

    return const AssistantResult(intent: AssistantIntent.unknown);
  }

  VoiceReminderDraft? parseReminder(String rawText) {
    final normalized = _normalize(rawText);
    if (!_looksLikeReminderCommand(normalized)) return null;

    final structured =
        _parseStructuredReminder(rawText) ??
        _parseInlineStructuredReminder(rawText);
    if (structured != null) return structured;

    var body = rawText.trim();
    body = body.replaceAll(
      RegExp(
        r'^\s*(add reminder|add a reminder|magdagdag ng paalala)\s*[:,-]?\s*',
        caseSensitive: false,
      ),
      '',
    );
    body = body.replaceAll(
      RegExp(
        r'^\s*(remind me to|paalalahanan mo ako na)\s+',
        caseSensitive: false,
      ),
      '',
    );
    body = body.trim();
    if (body.isEmpty) return null;

    final scheduledAt = _extractDateTime(normalized);
    final frequency = _extractFrequency(normalized);
    final title = _cleanTitle(body);
    if (title.isEmpty) return null;

    return VoiceReminderDraft(
      title: _capitalize(title),
      note: '',
      scheduledAt: scheduledAt,
      repeatType: frequency.repeatType,
      repeatIntervalMinutes: frequency.repeatIntervalMinutes,
      frequencyLabel: frequency.label,
      originalText: rawText,
    );
  }

  Future<String> answerOnline(String rawText) async {
    final normalized = _normalize(rawText);
    final isTagalog =
        TtsLanguageService.currentLanguage == AppSpeechLanguage.tagalog;

    try {
      if (normalized.contains('weather') || normalized.contains('panahon')) {
        final city = _extractWeatherCity(rawText);
        return await _weather(city, isTagalog);
      }

      if (normalized.contains('time') || normalized.contains('oras')) {
        return isTagalog
            ? 'Ang oras ngayon ay ${DateFormat('h:mm a').format(DateTime.now())}.'
            : 'The time now is ${DateFormat('h:mm a').format(DateTime.now())}.';
      }

      if (normalized.contains('day today') ||
          normalized.contains('date today') ||
          normalized.contains('anong araw') ||
          normalized.contains('what day')) {
        final date = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
        return isTagalog ? 'Ngayon ay $date.' : 'Today is $date.';
      }

      if (normalized.contains('latest news') ||
          normalized.contains('news today') ||
          normalized.contains('balita')) {
        return await _latestNews(isTagalog);
      }

      return await _wikipediaSummary(rawText, isTagalog);
    } catch (_) {
      return isTagalog
          ? 'Hindi ako makakonekta sa internet ngayon. Maaari pa rin akong gumawa ng mga paalala offline.'
          : 'I cannot reach the internet right now. I can still create reminders offline.';
    }
  }

  bool _looksLikeReminderCommand(String text) {
    return text.contains('add reminder') ||
        text.contains('add a reminder') ||
        text.startsWith('remind me') ||
        text.contains('magdagdag ng paalala') ||
        text.contains('paalalahanan');
  }

  ReminderQueryType? _reminderQueryType(String text) {
    if (text.contains('reminders today') ||
        text.contains('schedule today') ||
        text.contains('mga paalala ngayon') ||
        text.contains('iskedyul ngayon')) {
      return ReminderQueryType.today;
    }
    if (text.contains('task is next') ||
        text.contains('next reminder') ||
        text.contains('susunod na paalala')) {
      return ReminderQueryType.next;
    }
    if (text.contains('medicine should i take') ||
        text.contains('gamot') && text.contains('ngayon')) {
      return ReminderQueryType.medicineNow;
    }
    if (text.contains('how many pending') ||
        text.contains('pending reminders') ||
        text.contains('ilang') && text.contains('nakabinbin')) {
      return ReminderQueryType.pendingCount;
    }
    return null;
  }

  bool _isInternetQuery(String text) {
    return text.contains('weather') ||
        text.contains('panahon') ||
        text.contains('what time') ||
        text.contains('oras') ||
        text.contains('what day') ||
        text.contains('date today') ||
        text.contains('what is') ||
        text.contains('ano ang') ||
        text.contains('latest news') ||
        text.contains('news today') ||
        text.contains('balita');
  }

  DateTime _extractDateTime(String text) {
    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day);
    if (text.contains('tomorrow') || text.contains('bukas')) {
      date = date.add(const Duration(days: 1));
    }

    var hour = now.add(const Duration(hours: 1)).hour;
    var minute = 0;
    final timeMatch = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    ).firstMatch(text);
    if (timeMatch != null) {
      hour = int.tryParse(timeMatch.group(1) ?? '') ?? hour;
      minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final suffix = timeMatch.group(3) ?? '';
      if (suffix == 'pm' && hour < 12) hour += 12;
      if (suffix == 'am' && hour == 12) hour = 0;
    } else if (text.contains('morning') || text.contains('umaga')) {
      hour = 8;
      minute = 0;
    } else if (text.contains('evening') || text.contains('gabi')) {
      hour = 18;
      minute = 0;
    }

    var scheduled = DateTime(date.year, date.month, date.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  _Frequency _extractFrequency(String text) {
    if (text.contains('twice a month') || text.contains('twice monthly')) {
      return const _Frequency('twice_monthly', 21600, 'Twice a month');
    }
    if (text.contains('twice a day') ||
        text.contains('morning and evening') ||
        text.contains('umaga at gabi')) {
      return const _Frequency('custom:720', 720, 'Morning and evening');
    }
    if (text.contains('every hour') || text.contains('hourly')) {
      return const _Frequency('custom:60', 60, 'Every hour');
    }
    final hourlyMatch = RegExp(
      r'every\s+(\d+|one|two|three|four|five|six)\s+hours?',
    ).firstMatch(text);
    if (hourlyMatch != null) {
      final hours = _numberWord(hourlyMatch.group(1) ?? '1').clamp(1, 24);
      return _Frequency(
        'custom:${hours * 60}',
        hours * 60,
        'Every $hours hours',
      );
    }
    if (text.contains('every day') ||
        text.contains('daily') ||
        text.contains('araw-araw')) {
      return const _Frequency('daily', 1440, 'Every day');
    }
    if (text.contains('every week') || text.contains('weekly')) {
      return const _Frequency('weekly', 10080, 'Every week');
    }
    if (text.contains('every month') || text.contains('monthly')) {
      return const _Frequency('monthly', 43200, 'Every month');
    }
    return const _Frequency('none', 0, 'One time only');
  }

  VoiceReminderDraft? _parseStructuredReminder(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) return null;

    String? title;
    String note = '';
    DateTime? date;
    TimeParts? time;
    _Frequency frequency = const _Frequency('none', 0, 'One time only');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final normalized = _normalize(line);
      if (normalized == 'add reminder' ||
          normalized == 'add a reminder' ||
          normalized == 'magdagdag ng paalala') {
        title = _nextValue(lines, i);
        continue;
      }
      if (normalized == 'note' ||
          normalized == 'notes' ||
          normalized == 'tala') {
        note = _nextValue(lines, i) ?? '';
        continue;
      }
      if (normalized == 'today' || normalized == 'ngayon') {
        final now = DateTime.now();
        date = DateTime(now.year, now.month, now.day);
        continue;
      }
      if (normalized == 'tomorrow' || normalized == 'bukas') {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        date = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
        continue;
      }
      if (normalized.startsWith('time ') || normalized.startsWith('oras ')) {
        time = _extractTimeParts(normalized);
        continue;
      }
      if (normalized.startsWith('remind me') ||
          normalized.startsWith('paalalahanan')) {
        frequency = _extractFrequency(normalized);
      }
    }

    if (title == null || title.trim().isEmpty) return null;
    final now = DateTime.now();
    final selectedDate = date ?? DateTime(now.year, now.month, now.day);
    final selectedTime =
        time ??
        _extractTimeParts(_normalize(rawText)) ??
        TimeParts(now.add(const Duration(hours: 1)).hour, 0);
    var scheduled = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return VoiceReminderDraft(
      title: _capitalize(title.trim()),
      note: note.trim(),
      scheduledAt: scheduled,
      repeatType: frequency.repeatType,
      repeatIntervalMinutes: frequency.repeatIntervalMinutes,
      frequencyLabel: frequency.label,
      originalText: rawText,
    );
  }

  VoiceReminderDraft? _parseInlineStructuredReminder(String rawText) {
    final normalized = _normalize(rawText);
    if (!normalized.contains('add reminder') ||
        !normalized.contains('time ') && !normalized.contains('oras ')) {
      return null;
    }

    final titleMatch = RegExp(
      r'add (?:a )?reminder\s+(.+?)(?:\s+note\s+|\s+tala\s+|\s+today\b|\s+tomorrow\b|\s+ngayon\b|\s+bukas\b|\s+time\s+|\s+oras\s+|$)',
      caseSensitive: false,
    ).firstMatch(rawText);
    final noteMatch = RegExp(
      r'(?:note|tala)\s+(.+?)(?:\s+today\b|\s+tomorrow\b|\s+ngayon\b|\s+bukas\b|\s+time\s+|\s+oras\s+|\s+remind me\s+|$)',
      caseSensitive: false,
    ).firstMatch(rawText);
    final title = titleMatch?.group(1)?.trim();
    if (title == null || title.isEmpty) return null;

    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day);
    if (normalized.contains('tomorrow') || normalized.contains('bukas')) {
      final tomorrow = now.add(const Duration(days: 1));
      date = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }
    final time = _extractTimeParts(normalized);
    final selectedTime =
        time ?? TimeParts(now.add(const Duration(hours: 1)).hour, 0);
    var scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    final frequency = _extractFrequency(normalized);

    return VoiceReminderDraft(
      title: _capitalize(title),
      note: noteMatch?.group(1)?.trim() ?? '',
      scheduledAt: scheduled,
      repeatType: frequency.repeatType,
      repeatIntervalMinutes: frequency.repeatIntervalMinutes,
      frequencyLabel: frequency.label,
      originalText: rawText,
    );
  }

  String? _nextValue(List<String> lines, int index) {
    if (index + 1 >= lines.length) return null;
    final next = lines[index + 1].trim();
    final normalized = _normalize(next);
    const reserved = {
      'add reminder',
      'add a reminder',
      'note',
      'notes',
      'today',
      'tomorrow',
      'ngayon',
      'bukas',
    };
    if (reserved.contains(normalized) ||
        normalized.startsWith('time ') ||
        normalized.startsWith('remind me')) {
      return null;
    }
    return next;
  }

  TimeParts? _extractTimeParts(String text) {
    final match = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    ).firstMatch(text);
    if (match == null) return null;
    var hour = int.tryParse(match.group(1) ?? '') ?? 0;
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    final suffix = match.group(3) ?? '';
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    return TimeParts(hour.clamp(0, 23), minute.clamp(0, 59));
  }

  int _numberWord(String value) {
    switch (value) {
      case 'one':
        return 1;
      case 'two':
        return 2;
      case 'three':
        return 3;
      case 'four':
        return 4;
      case 'five':
        return 5;
      case 'six':
        return 6;
      default:
        return int.tryParse(value) ?? 1;
    }
  }

  String _cleanTitle(String text) {
    var title = text;
    final patterns = [
      r'\bat\s+\d{1,2}(:\d{2})?\s*(am|pm)\b',
      r'\btomorrow\b',
      r'\bbukas\b',
      r'\bevery\s+(hour|day|week|month)\b',
      r'\bevery\s+(\d+|one|two|three|four|five|six)\s+hours?\b',
      r'\bdaily\b',
      r'\bhourly\b',
      r'\bweekly\b',
      r'\bmonthly\b',
      r'\btwice\s+a\s+(day|month)\b',
      r'\bmorning and evening\b',
      r'\bremind\s+every\s+\w+\b',
      r'\bremind\s+me\s+every\s+\w+\b',
    ];
    for (final pattern in patterns) {
      title = title.replaceAll(RegExp(pattern, caseSensitive: false), '');
    }
    return title.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _extractWeatherCity(String rawText) {
    final match = RegExp(
      r'\b(?:in|sa)\s+([a-zA-Z\s]+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    return match?.group(1)?.trim().isNotEmpty == true
        ? match!.group(1)!.trim()
        : 'Manila';
  }

  Future<String> _weather(String city, bool isTagalog) async {
    final uri = Uri.https('wttr.in', '/$city', {'format': 'j1'});
    final data = await _getJson(uri);
    final current = (data['current_condition'] as List).first as Map;
    final temp = current['temp_C'];
    final desc = ((current['weatherDesc'] as List).first as Map)['value'];
    return isTagalog
        ? 'Ang panahon sa $city ngayon ay $desc, mga $temp degrees Celsius.'
        : 'The weather in $city is $desc, about $temp degrees Celsius.';
  }

  Future<String> _latestNews(bool isTagalog) async {
    final uri = Uri.https('news.google.com', '/rss', {
      'hl': 'en-PH',
      'gl': 'PH',
      'ceid': 'PH:en',
    });
    final xml = await _getText(uri);
    final titles = RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>')
        .allMatches(xml)
        .map((m) => m.group(1) ?? '')
        .where(
          (title) => title.isNotEmpty && title != 'Top stories - Google News',
        )
        .take(3)
        .toList();
    if (titles.isEmpty) throw const FormatException('No news titles');
    final joined = titles.join('. ');
    return isTagalog
        ? 'Narito ang ilang pinakabagong balita: $joined.'
        : 'Here are a few latest headlines: $joined.';
  }

  Future<String> _wikipediaSummary(String rawText, bool isTagalog) async {
    var topic = rawText
        .replaceAll(RegExp(r'what is|who is|ano ang', caseSensitive: false), '')
        .trim();
    if (topic.isEmpty) topic = rawText.trim();
    final uri = Uri.https(
      'en.wikipedia.org',
      '/api/rest_v1/page/summary/${Uri.encodeComponent(topic)}',
    );
    final data = await _getJson(uri);
    final extract = data['extract']?.toString();
    if (extract == null || extract.isEmpty) {
      throw const FormatException('No summary');
    }
    final answer = extract.length > 360
        ? '${extract.substring(0, 357)}...'
        : extract;
    return isTagalog ? 'Ayon sa online summary: $answer' : answer;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final text = await _getText(uri);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<String> _getText(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.userAgentHeader, 'LifeEase Assistant');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

class _Frequency {
  const _Frequency(this.repeatType, this.repeatIntervalMinutes, this.label);

  final String repeatType;
  final int repeatIntervalMinutes;
  final String label;
}

class TimeParts {
  const TimeParts(this.hour, this.minute);

  final int hour;
  final int minute;
}
