import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:lifeease/core/constants/env_config.dart';

class GemmaNlpParseResult {
  const GemmaNlpParseResult({
    this.data,
    this.errorMessage,
    this.statusCode,
    this.modelAttempted,
  });

  final Map<String, dynamic>? data;
  final String? errorMessage;
  final int? statusCode;
  final String? modelAttempted;

  bool get isSuccess =>
      data != null && data!['usedFallback'] != true;
}

/// Lightweight Gemma 2 NLP client via Google's Generative Language API.
///
/// Uses [GEMINI_API_KEY] from env.json and defaults to `gemma-2-2b-it`.
class GemmaNlpService {
  GemmaNlpService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _modelChain = [
    'gemma-2-2b-it',
    'gemini-2.0-flash-lite',
    'gemini-2.0-flash',
  ];

  String? _lastErrorMessage;
  int? _lastStatusCode;
  String? _lastModelAttempted;

  bool get isAvailable => EnvConfig.hasRealValue('GEMINI_API_KEY');

  String? get lastErrorMessage => _lastErrorMessage;
  int? get lastStatusCode => _lastStatusCode;
  String? get lastModelAttempted => _lastModelAttempted;

  String get modelName {
    final configured = EnvConfig.maybeGet('GEMMA_MODEL')?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return _modelChain.first;
  }

  /// Parses spoken voice command text into structured intent JSON.
  Future<GemmaNlpParseResult> parseCommand(String text) async {
    final trimmed = text.trim();
    _lastErrorMessage = null;
    _lastStatusCode = null;
    _lastModelAttempted = null;

    if (!isAvailable || trimmed.isEmpty) {
      return GemmaNlpParseResult(
        errorMessage: isAvailable
            ? 'Empty voice command text.'
            : 'GEMINI_API_KEY is missing in env.json.',
      );
    }

    final apiKey = EnvConfig.geminiApiKey!;
    final models = <String>{
      modelName,
      ..._modelChain,
    }.toList();

    String? lastError;
    int? lastStatus;

    for (final model in models) {
      _lastModelAttempted = model;
      final result = await _request(apiKey, model, trimmed);
      if (result.isSuccess) return result;

      lastError = result.errorMessage ?? lastError;
      lastStatus = result.statusCode ?? lastStatus;
    }

    _lastErrorMessage = lastError ?? 'Gemma request failed.';
    _lastStatusCode = lastStatus;

    if (kDebugMode) {
      debugPrint(
        'GemmaNlpService failed (status $_lastStatusCode, '
        'model $_lastModelAttempted): $_lastErrorMessage',
      );
    }

    return GemmaNlpParseResult(
      errorMessage: _lastErrorMessage,
      statusCode: _lastStatusCode,
      modelAttempted: _lastModelAttempted,
    );
  }

  Future<GemmaNlpParseResult> _request(
    String apiKey,
    String model,
    String text,
  ) async {
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [{'text': _buildPrompt(text)}],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 280,
        'responseMimeType': 'application/json',
      },
    });

    try {
      var response = await _client.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$model:generateContent',
        ),
        headers: {
          'x-goog-api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        response = await _client.post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/'
            '$model:generateContent?key=${Uri.encodeQueryComponent(apiKey)}',
          ),
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
      }

      if (response.statusCode != 200) {
        return GemmaNlpParseResult(
          statusCode: response.statusCode,
          modelAttempted: model,
          errorMessage: _extractApiError(response.body, response.statusCode),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = _extractContent(data);
      final parsed = _parseJsonObject(content);
      if (parsed == null) {
        return GemmaNlpParseResult(
          statusCode: response.statusCode,
          modelAttempted: model,
          errorMessage: 'Gemma returned a response that could not be parsed.',
        );
      }

      final intent = _normalizeIntent(parsed['intent']);
      if (intent == 'unknown') {
        return GemmaNlpParseResult(
          statusCode: response.statusCode,
          modelAttempted: model,
          errorMessage: 'Gemma could not determine the command intent.',
        );
      }

      return GemmaNlpParseResult(
        data: {
          'intent': intent,
          'task': _stringOrNull(parsed['task']) ??
              (text.length <= 120 ? text : '${text.substring(0, 117)}...'),
          'summary': _stringOrNull(parsed['summary']) ??
              (text.length <= 120 ? text : '${text.substring(0, 117)}...'),
          'time': _stringOrNull(parsed['time']),
          'repeat': _stringOrNull(parsed['repeat']),
          'confidence': _numberOrDefault(parsed['confidence'], 0.78),
          'language': _stringOrNull(parsed['language']) ?? 'unknown',
          'model': model,
          'usedFallback': false,
        },
        modelAttempted: model,
      );
    } catch (error) {
      return GemmaNlpParseResult(
        modelAttempted: model,
        errorMessage: 'Network error calling Gemma: $error',
      );
    }
  }

  String _extractApiError(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message']?.toString().trim();
          if (message != null && message.isNotEmpty) {
            return 'HTTP $statusCode: $message';
          }
        }
      }
    } catch (_) {
      // Ignore JSON parse errors and fall back to generic message.
    }
    return 'HTTP $statusCode: Gemma API request failed.';
  }

  String _buildPrompt(String text) {
    return [
      'You are the LifeEase PH voice command parser powered by Gemma 2.',
      'Recognize English, Tagalog, and mixed English-Tagalog spoken commands.',
      'Summarize the command in one short sentence (max 90 characters).',
      'Return only valid JSON with these keys:',
      'intent, task, summary, time, repeat, confidence, language.',
      'Allowed intents:',
      'create_reminder, call_emergency, translate, summarize,',
      'reminder_list, daily_schedule, navigation, statistics,',
      'internet_query, unknown.',
      'task: the core action or reminder title (e.g. "Take medicine", "Uminom ng gamot").',
      'time: 12-hour format like "8:00 AM" when mentioned, else null.',
      'repeat: daily, weekly, monthly, or null.',
      'confidence: number from 0 to 1.',
      'language: en, tl, mixed, or unknown.',
      'User text: ${jsonEncode(text)}',
    ].join('\n');
  }

  String _extractContent(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List<dynamic>?;
    final first = candidates?.isNotEmpty == true
        ? candidates!.first as Map<String, dynamic>?
        : null;
    final content = first?['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    for (final part in parts ?? const []) {
      final text = (part as Map<String, dynamic>)['text'];
      if (text is String && text.trim().isNotEmpty) return text;
    }
    return '';
  }

  Map<String, dynamic>? _parseJsonObject(String content) {
    final trimmed = content.trim();
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(1);
    final candidate = fenced ?? trimmed;
    final objectMatch = RegExp(r'\{[\s\S]*\}').firstMatch(candidate);
    if (objectMatch == null) return null;
    try {
      return jsonDecode(objectMatch.group(0)!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _normalizeIntent(Object? value) {
    final intent = (value?.toString() ?? 'unknown').toLowerCase();
    const allowed = {
      'create_reminder',
      'call_emergency',
      'translate',
      'summarize',
      'reminder_list',
      'daily_schedule',
      'navigation',
      'statistics',
      'internet_query',
      'unknown',
    };
    if (allowed.contains(intent)) return intent;
    if (intent == 'add_reminder' || intent == 'hydration_reminder') {
      return 'create_reminder';
    }
    if (intent == 'emergency') return 'call_emergency';
    return 'unknown';
  }

  String? _stringOrNull(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
    return trimmed;
  }

  double _numberOrDefault(Object? value, double fallback) {
    if (value is! num || value.isNaN) return fallback;
    return value.toDouble().clamp(0.0, 1.0);
  }
}
