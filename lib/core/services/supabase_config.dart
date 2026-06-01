import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifeease/core/constants/env_config.dart';

class SupabaseConfig {
  static bool _initialized = false;

  static bool get isConfigured {
    final url = EnvConfig.maybeGet('SUPABASE_URL');

    return _isValidSupabaseUrl(url) &&
        EnvConfig.hasRealValue('SUPABASE_ANON_KEY');
  }

  static bool get isInitialized => _initialized;

  static SupabaseClient? get maybeClient {
    if (!_initialized) return null;
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    if (!isConfigured) {
      if (kDebugMode) {
        print(
          'Supabase is not configured. Starting LifeEase in guest/offline mode.',
        );
      }
      return;
    }

    try {
      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        anonKey: EnvConfig.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );

      _initialized = true;
    } catch (error) {
      if (kDebugMode) {
        print('SUPABASE INITIALIZATION ERROR: $error');
        print('Starting LifeEase in guest/offline mode.');
      }
    }
  }

  static bool _isValidSupabaseUrl(String? value) {
    if (EnvConfig.isPlaceholder(value)) return false;

    final uri = Uri.tryParse(value!);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
