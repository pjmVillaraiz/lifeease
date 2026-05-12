import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifeease/core/services/supabase_config.dart';

class LifeEaseAuthResult {
  final bool success;
  final bool isGuest;
  final String? message;

  const LifeEaseAuthResult({
    required this.success,
    this.isGuest = false,
    this.message,
  });
}

class SupabaseAuthService {
  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  bool get isConfigured => SupabaseConfig.isInitialized;

  User? get currentUser => _client?.auth.currentUser;

  Stream<AuthState> get authStateChanges {
    final client = _client;
    if (client == null) return const Stream<AuthState>.empty();
    return client.auth.onAuthStateChange;
  }

  Future<LifeEaseAuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      return const LifeEaseAuthResult(
        success: false,
        message: 'Supabase is not configured. Guest mode is available.',
      );
    }

    try {
      await client.auth.signInWithPassword(email: email, password: password);
      return const LifeEaseAuthResult(success: true);
    } on AuthException catch (error) {
      return LifeEaseAuthResult(success: false, message: error.message);
    } catch (_) {
      return const LifeEaseAuthResult(
        success: false,
        message: 'Unable to sign in. Check your internet connection.',
      );
    }
  }

  Future<LifeEaseAuthResult> registerWithEmail({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final client = _client;
    if (client == null) {
      return const LifeEaseAuthResult(
        success: false,
        message: 'Supabase is not configured. Guest mode is available.',
      );
    }

    try {
      final displayName = [firstName, lastName]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .map((part) => part.trim())
          .join(' ');
      await client.auth.signUp(
        email: email,
        password: password,
        data: {
          if (firstName?.trim().isNotEmpty == true)
            'first_name': firstName!.trim(),
          if (lastName?.trim().isNotEmpty == true) 'last_name': lastName!.trim(),
          if (displayName.isNotEmpty) 'display_name': displayName,
        },
      );
      return const LifeEaseAuthResult(success: true);
    } on AuthException catch (error) {
      return LifeEaseAuthResult(success: false, message: error.message);
    } catch (_) {
      return const LifeEaseAuthResult(
        success: false,
        message: 'Unable to register. Check your internet connection.',
      );
    }
  }

  Future<LifeEaseAuthResult> signInWithGoogle() async {
    final client = _client;
    if (client == null) {
      return const LifeEaseAuthResult(
        success: false,
        message: 'Supabase is not configured. Guest mode is available.',
      );
    }

    try {
      final started = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.lifeease://login-callback/',
      );
      return LifeEaseAuthResult(
        success: started,
        message: started ? null : 'Google sign-in could not be started.',
      );
    } on AuthException catch (error) {
      return LifeEaseAuthResult(success: false, message: error.message);
    } catch (_) {
      return const LifeEaseAuthResult(
        success: false,
        message: 'Unable to start Google sign-in.',
      );
    }
  }

  Future<LifeEaseAuthResult> continueAsGuest() async {
    final client = _client;
    if (client == null) {
      return const LifeEaseAuthResult(success: true, isGuest: true);
    }
    try {
      await client.auth.signInAnonymously();
      return const LifeEaseAuthResult(success: true, isGuest: true);
    } catch (_) {
      return const LifeEaseAuthResult(success: true, isGuest: true);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _client?.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }
}
