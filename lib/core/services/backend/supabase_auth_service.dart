import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _sessionModeKey = 'auth.sessionMode';
  static const String _userMode = 'user';
  static const String _guestMode = 'guest';

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  bool get isConfigured => SupabaseConfig.isInitialized;

  User? get currentUser => _client?.auth.currentUser;

  Future<bool> get isGuestSession async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionModeKey) == _guestMode;
  }

  Future<bool> shouldStartAtHome() async {
    if (await isGuestSession) return true;
    return currentUser != null;
  }

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
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await _setSessionMode(_userMode);
      await _ensureUserProfile(
        user: response.user ?? client.auth.currentUser,
        email: email,
      );
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
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: {
          if (firstName?.trim().isNotEmpty == true)
            'first_name': firstName!.trim(),
          if (lastName?.trim().isNotEmpty == true) 'last_name': lastName!.trim(),
          if (displayName.isNotEmpty) 'display_name': displayName,
        },
      );
      await _setSessionMode(_userMode);
      await _ensureUserProfile(
        user: response.user ?? client.auth.currentUser,
        email: email,
        firstName: firstName,
        lastName: lastName,
        displayName: displayName,
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
      if (started) {
        await _setSessionMode(_userMode);
      }
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
      await _setSessionMode(_guestMode);
      return const LifeEaseAuthResult(success: true, isGuest: true);
    }
    try {
      if (client.auth.currentUser != null) {
        await client.auth.signOut();
      }
      await client.auth.signInAnonymously();
      await _setSessionMode(_guestMode);
      return const LifeEaseAuthResult(success: true, isGuest: true);
    } catch (_) {
      await _setSessionMode(_guestMode);
      return const LifeEaseAuthResult(success: true, isGuest: true);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _client?.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    try {
      await _client?.auth.signOut();
    } finally {
      await _clearSessionMode();
    }
  }

  Future<void> _setSessionMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionModeKey, mode);
  }

  Future<void> _clearSessionMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionModeKey);
  }

  Future<void> _ensureUserProfile({
    required User? user,
    required String email,
    String? firstName,
    String? lastName,
    String? displayName,
  }) async {
    final client = _client;
    if (client == null || user == null) return;

    try {
      await client.from('users').upsert({
        'id': user.id,
        'email': email.trim(),
        if (firstName?.trim().isNotEmpty == true)
          'first_name': firstName!.trim(),
        if (lastName?.trim().isNotEmpty == true) 'last_name': lastName!.trim(),
        if (displayName?.trim().isNotEmpty == true)
          'display_name': displayName!.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Profile sync is retried from the profile screen; auth should still pass.
    }
  }
}
