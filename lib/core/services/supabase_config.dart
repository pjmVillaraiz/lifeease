import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'package:lifeease/core/constants/env_config.dart';

class SupabaseConfig {
  static bool _initialized = false;

  static bool get isConfigured {
    final url = EnvConfig.maybeGet('SUPABASE_URL');
    final anonKey = EnvConfig.maybeGet('SUPABASE_ANON_KEY');

    return _isValidSupabaseUrl(url) && !EnvConfig.isPlaceholder(anonKey);
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
      final url = EnvConfig.get('SUPABASE_URL');
      final anonKey = EnvConfig.get('SUPABASE_ANON_KEY');

      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );

      _initialized = true;

      // Perform a robust connection test with a short timeout
      // If it fails or times out, we just continue in guest mode
      await _testConnection().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Connection test timed out'),
      );
    } catch (e) {
      if (kDebugMode) {
        print('🚨 SUPABASE INITIALIZATION ERROR: $e');
        print('Starting LifeEase in guest/offline mode.');
      }
      // Note: _initialized remains true if Supabase.initialize succeeded
      // but the connection test failed.
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
        print('⚡ Testing Supabase connection...');
      }

      // A simple non-destructive query to verify DB connection and anon key
      // If the 'users' or 'reminders' table exists, this will return quickly.
      // We limit to 1 to just check if the endpoint is reachable.
      await client.from('reminders').select('id').limit(1);

      if (kDebugMode) {
        print('✅ Supabase connected successfully!');
      }
    } on PostgrestException catch (e) {
      // If we get a PostgrestException, it means we connected to the database successfully,
      // but maybe the table doesn't exist or RLS blocked it. That's fine, connection is verified.
      if (e.code == 'PGRST116' || e.code == '42P01') {
        if (kDebugMode) {
          print(
            '⚠️ Supabase connected, but got DB error (Table missing or RLS): \${e.message}',
          );
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Supabase Postgrest Error: \${e.message}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🚨 SUPABASE CONNECTION TEST FAILED: \$e');
      }
      // Rethrow to alert the developer that the URL might be unreachable
      throw Exception(
        'Supabase endpoint unreachable. Are you connected to the internet? Error: \$e',
      );
    }
  }
}
