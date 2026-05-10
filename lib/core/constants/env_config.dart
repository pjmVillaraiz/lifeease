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
    } catch (e) {
      throw Exception(
        '🚨 CRITICAL ERROR: Failed to load env.json!\n'
        'Ensure that env.json exists in the project root, is valid JSON, and is added to pubspec.yaml assets.\n'
        'Error details: \$e'
      );
    }
  }

  static String get(String key) {
    final dartDefine = String.fromEnvironment(key);
    if (dartDefine.isNotEmpty) return dartDefine;
    
    if (_assetValues == null) {
      throw Exception('EnvConfig.load() must be called before accessing keys.');
    }
    
    final value = _assetValues![key]?.toString();
    if (value == null || value.trim().isEmpty) {
      throw Exception('🚨 CRITICAL ERROR: Missing or empty environment key: \$key');
    }
    
    return value;
  }
}
