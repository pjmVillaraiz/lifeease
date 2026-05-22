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

      // Perform a robust connection test with a short timeout.
      // If it fails or times out, we continue in guest mode.
      await _testConnection().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Connection test timed out'),
      );
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

  static Future<void> _testConnection() async {
    final client = maybeClient;
    if (client == null) {
      throw Exception('SupabaseClient is null after initialization.');
    }

    try {
      if (kDebugMode) {
        print('Testing Supabase connection...');
      }

      // A simple non-destructive query to verify DB connection and anon key.
      await client.from('reminders').select('id').limit(1);

      if (kDebugMode) {
        print('Supabase connected successfully.');
      }
    } on PostgrestException catch (error) {
      // Postgrest errors still prove the endpoint and anon key were reached.
      if (error.code == 'PGRST116' || error.code == '42P01') {
        if (kDebugMode) {
          print(
            'Supabase connected, but got DB error (table missing or RLS): ${error.message}',
          );
        }
      } else {
        if (kDebugMode) {
          print('Supabase Postgrest error: ${error.message}');
        }
      }
    } catch (error) {
      if (kDebugMode) {
        print('SUPABASE CONNECTION TEST FAILED: $error');
      }
      throw Exception(
        'Supabase endpoint unreachable. Are you connected to the internet? Error: $error',
      );
    }
  }
}
