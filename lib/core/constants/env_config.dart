import 'dart:convert';

import 'package:flutter/services.dart';

class EnvConfig {
  static Map<String, dynamic>? _assetValues;

  static Future<void> load() async {
    if (_assetValues != null) return;

    try {
      final raw = await rootBundle.loadString('env.json');
      final Map<String, dynamic> jsonMap = jsonDecode(raw);
      _assetValues = jsonMap;
    } catch (error) {
      throw Exception(
        'CRITICAL ERROR: Failed to load env.json.\n'
        'Ensure that env.json exists in the project root, is valid JSON, and is added to pubspec.yaml assets.\n'
        'Error details: $error',
      );
    }
  }

  static String get(String key) {
    final dartDefine = String.fromEnvironment(key);
    if (dartDefine.isNotEmpty) return dartDefine.trim();

    if (_assetValues == null) {
      throw Exception('EnvConfig.load() must be called before accessing keys.');
    }

    final value = _assetValues![key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw Exception('CRITICAL ERROR: Missing or empty environment key: $key');
    }

    return value;
  }

  static String? maybeGet(String key) {
    final dartDefine = String.fromEnvironment(key);
    if (dartDefine.isNotEmpty) return dartDefine.trim();

    final value = _assetValues?[key]?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static bool isPlaceholder(String? value) {
    if (value == null || value.trim().isEmpty) return true;

    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('your_') ||
        normalized.startsWith('your-') ||
        normalized.contains('_here') ||
        normalized.contains('-here');
  }

  static bool hasRealValue(String key) {
    return !isPlaceholder(maybeGet(key));
  }

  static String get supabaseUrl => get('SUPABASE_URL');
  static String get supabaseAnonKey => get('SUPABASE_ANON_KEY');

  static String? get openAiApiKey => maybeGet('OPENAI_API_KEY');
  static String? get geminiApiKey => maybeGet('GEMINI_API_KEY');
  static String? get anthropicApiKey => maybeGet('ANTHROPIC_API_KEY');
  static String? get perplexityApiKey => maybeGet('PERPLEXITY_API_KEY');
  static String? get googleWebClientId => maybeGet('GOOGLE_WEB_CLIENT_ID');
}
