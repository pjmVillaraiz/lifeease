import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifeease/core/constants/env_config.dart';

class SupabaseConfig {
  static bool _initialized = false;

  static bool get isConfigured =>
      EnvConfig.get('SUPABASE_URL').isNotEmpty &&
      EnvConfig.get('SUPABASE_ANON_KEY').isNotEmpty;

  static bool get isInitialized => _initialized;

  static SupabaseClient? get maybeClient {
    if (!_initialized) return null;
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    await Hive.initFlutter();
    if (_initialized || !isConfigured) return;

    await Supabase.initialize(
      url: EnvConfig.get('SUPABASE_URL'),
      anonKey: EnvConfig.get('SUPABASE_ANON_KEY'),
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _initialized = true;
  }
}
