import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeease/core/constants/env_config.dart';
import 'package:lifeease/features/reminders/models/reminder_model.dart';
import 'package:lifeease/features/reminders/application/reminder_insights_service.dart';
import 'package:lifeease/shared/providers/language_controller.dart';

class AiSuggestionService {
  AiSuggestionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _cacheKey = 'ai_suggestion_cache';
  static const String _cacheTimeKey = 'ai_suggestion_time';
  static const Duration _cacheDuration = Duration(hours: 6);

  Future<String?> fetchSuggestion(List<ReminderModel> reminders, ReminderStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedTime = prefs.getInt(_cacheTimeKey);
    final cachedSuggestion = prefs.getString(_cacheKey);

    if (cachedTime != null && cachedSuggestion != null) {
      final cacheDate = DateTime.fromMillisecondsSinceEpoch(cachedTime);
      if (DateTime.now().difference(cacheDate) < _cacheDuration) {
        return cachedSuggestion;
      }
    }

    final suggestion = await _generateSuggestion(reminders, stats);
    if (suggestion != null && suggestion.trim().isNotEmpty) {
      await prefs.setString(_cacheKey, suggestion.trim());
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      return suggestion.trim();
    }

    return cachedSuggestion;
  }

  Future<String?> _generateSuggestion(List<ReminderModel> reminders, ReminderStats stats) async {
    final apiKeys = EnvConfig.geminiApiKeys;
    if (apiKeys.isEmpty) return null;

    final isTagalog = LanguageController.isTagalog.value;
    final prompt = _buildPrompt(reminders, stats, isTagalog);

    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [{'text': prompt}],
        },
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 150,
      },
    });

    final models = [
      'gemini-2.5-flash',
      'gemini-2.0-flash-lite',
      'gemini-2.0-flash',
      'gemini-1.5-flash',
    ];

    for (final apiKey in apiKeys) {
      for (final model in models) {
        try {
          final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${Uri.encodeQueryComponent(apiKey)}';
          final response = await _client.post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: body,
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final suggestion = _extractContent(data);
            if (suggestion != null && suggestion.trim().isNotEmpty) {
              return suggestion;
            }
          }
        } catch (_) {
          // Continue to next model or API key
        }
      }
    }

    return null;
  }

  String _buildPrompt(List<ReminderModel> reminders, ReminderStats stats, bool isTagalog) {
    final language = isTagalog ? 'Tagalog' : 'English';
    
    // Gather up to 5 upcoming tasks
    final now = DateTime.now().millisecondsSinceEpoch;
    final upcoming = reminders
        .where((r) => r.scheduledTimeMillis >= now && !r.isCompleted && !r.isCanceled)
        .toList()
      ..sort((a, b) => a.scheduledTimeMillis.compareTo(b.scheduledTimeMillis));
    
    final tasksList = upcoming.take(5).map((r) => r.title).join(', ');

    return '''
You are LifeEase PH, a friendly and empathetic health and productivity AI assistant. 
Based on the user's schedule, generate a short, single-sentence (max 20 words) personalized suggestion or encouragement.
Do not use robotic phrasing. Be warm and supportive. 
Language to use: \$language.

User Context:
- Completion Rate Today: \${stats.completionRate}%
- Pending Tasks Today: \${stats.pending}
- Missed Tasks Today: \${stats.missed}
- Upcoming tasks: \${tasksList.isEmpty ? 'None' : tasksList}

Example outputs:
- "You're doing great! Don't forget to take a quick break and drink some water."
- "You have a few tasks coming up, try tackling them one step at a time."
- "Medyo marami kang naiwang paalala, baka kailangan mo ng pahinga muna."

Output only the suggestion string and nothing else.
''';
  }

  String? _extractContent(Map<String, dynamic> data) {
    try {
      final candidates = data['candidates'] as List<dynamic>?;
      final first = candidates?.firstOrNull as Map<String, dynamic>?;
      final content = first?['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      final text = parts?.firstOrNull?['text'] as String?;
      return text?.replaceAll('"', '').trim();
    } catch (_) {
      return null;
    }
  }
}
