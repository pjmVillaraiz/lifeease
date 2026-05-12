import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeease/core/services/backend/supabase_auth_service.dart';
import 'package:lifeease/core/services/supabase_config.dart';

class UserProfile {
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final String? email;
  final String? phone;
  final String? birthdate;
  final String? medicalConditions;

  const UserProfile({
    this.firstName,
    this.lastName,
    this.displayName,
    this.email,
    this.phone,
    this.birthdate,
    this.medicalConditions,
  });

  String? get resolvedDisplayName {
    final parts = [firstName, lastName]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .toList();
    if (parts.isNotEmpty) return parts.join(' ');
    return displayName?.trim().isEmpty == false ? displayName!.trim() : null;
  }

  String? get resolvedFirstName {
    if (firstName?.trim().isNotEmpty == true) return firstName!.trim();
    final name = resolvedDisplayName;
    if (name == null || name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }
}

class UserProfileService {
  static const String nameKey = 'profile.name';
  static const String firstNameKey = 'profile.firstName';
  static const String lastNameKey = 'profile.lastName';
  static const String emailKey = 'profile.email';
  static const String phoneKey = 'profile.phone';
  static const String birthdateKey = 'profile.birthdate';
  static const String conditionsKey = 'profile.conditions';

  final SupabaseAuthService _authService;

  UserProfileService({SupabaseAuthService? authService})
    : _authService = authService ?? SupabaseAuthService();

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _authService.currentUser;

    var profile = UserProfile(
      firstName: prefs.getString(firstNameKey),
      lastName: prefs.getString(lastNameKey),
      displayName: prefs.getString(nameKey),
      email: prefs.getString(emailKey) ?? user?.email,
      phone: prefs.getString(phoneKey),
      birthdate: prefs.getString(birthdateKey),
      medicalConditions: prefs.getString(conditionsKey),
    );

    final client = SupabaseConfig.maybeClient;
    if (client == null || user == null) return profile;

    try {
      final row = await client
          .from('users')
          .select(
            'email, first_name, last_name, display_name, phone, birthdate, medical_conditions',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (row == null) return profile;
      profile = UserProfile(
        firstName: row['first_name']?.toString(),
        lastName: row['last_name']?.toString(),
        displayName: row['display_name']?.toString(),
        email: row['email']?.toString() ?? user.email,
        phone: row['phone']?.toString(),
        birthdate: row['birthdate']?.toString(),
        medicalConditions: row['medical_conditions']?.toString(),
      );
      await saveProfile(profile, syncRemote: false);
    } catch (_) {
      return profile;
    }

    return profile;
  }

  Future<void> saveProfile(
    UserProfile profile, {
    bool syncRemote = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(firstNameKey, profile.firstName?.trim() ?? '');
    await prefs.setString(lastNameKey, profile.lastName?.trim() ?? '');
    await prefs.setString(nameKey, profile.resolvedDisplayName ?? '');
    await prefs.setString(emailKey, profile.email?.trim() ?? '');
    await prefs.setString(phoneKey, profile.phone?.trim() ?? '');
    await prefs.setString(birthdateKey, profile.birthdate?.trim() ?? '');
    await prefs.setString(
      conditionsKey,
      profile.medicalConditions?.trim() ?? '',
    );

    if (!syncRemote) return;

    final client = SupabaseConfig.maybeClient;
    final user = _authService.currentUser;
    if (client == null || user == null) return;

    await client.from('users').upsert({
      'id': user.id,
      'email': profile.email?.trim() ?? user.email,
      'first_name': profile.firstName?.trim(),
      'last_name': profile.lastName?.trim(),
      'display_name': profile.resolvedDisplayName,
      'phone': profile.phone?.trim(),
      'birthdate': profile.birthdate?.trim(),
      'medical_conditions': profile.medicalConditions?.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
