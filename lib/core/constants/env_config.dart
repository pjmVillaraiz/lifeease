import 'package:flutter/services.dart';

class EnvConfig {
  static Map<String, String>? _assetValues;

  static Future<void> load() async {
    if (_assetValues != null) return;
    _assetValues = {};

    try {
      final raw = await rootBundle.loadString('assets/.env');
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final separator = trimmed.indexOf('=');
        if (separator <= 0) continue;
        final key = trimmed.substring(0, separator).trim();
        final value = trimmed.substring(separator + 1).trim();
        _assetValues![key] = value;
      }
    } catch (_) {
      // Optional in local demo builds. Production can provide --dart-define
      // values or bundle assets/.env through CI secret injection.
    }
  }

  static String get(String key) {
    final dartDefine = String.fromEnvironment(key);
    if (dartDefine.isNotEmpty) return dartDefine;
    return _assetValues?[key] ?? '';
  }
}
