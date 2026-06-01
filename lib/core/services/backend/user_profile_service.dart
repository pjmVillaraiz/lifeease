import 'dart:convert';

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

class UserEmergencyContact {
  final String name;
  final String relationship;
  final String phone;
  final String avatarUrl;

  const UserEmergencyContact({
    required this.name,
    required this.relationship,
    required this.phone,
    required this.avatarUrl,
  });

  factory UserEmergencyContact.fromMap(Map<String, dynamic> map) {
    return UserEmergencyContact(
      name: map['name']?.toString() ?? '',
      relationship: map['relationship']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      avatarUrl: map['avatarUrl']?.toString() ?? '',
    );
  }

  Map<String, String> toMap() => {
    'name': name,
    'relationship': relationship,
    'phone': phone,
    'avatarUrl': avatarUrl,
  };
}

class UserProfileService {
  static const String nameKey = 'profile.name';
  static const String firstNameKey = 'profile.firstName';
  static const String lastNameKey = 'profile.lastName';
  static const String emailKey = 'profile.email';
  static const String phoneKey = 'profile.phone';
  static const String birthdateKey = 'profile.birthdate';
  static const String conditionsKey = 'profile.conditions';
  static const String emergencyContactsKey = 'profile.emergencyContacts';

  final SupabaseAuthService _authService;

  UserProfileService({SupabaseAuthService? authService})
    : _authService = authService ?? SupabaseAuthService();

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _authService.currentUser;
    final isGuest = await _authService.isGuestSession;
    final prefix = await _storagePrefix();

    var profile = UserProfile(
      firstName: _readString(prefs, prefix, firstNameKey),
      lastName: _readString(prefs, prefix, lastNameKey),
      displayName:
          _readString(prefs, prefix, nameKey) ??
          (isGuest ? 'Guest User' : null),
      email:
          _readString(prefs, prefix, emailKey) ??
          (isGuest ? 'Guest Mode' : user?.email),
      phone: _readString(prefs, prefix, phoneKey),
      birthdate: _readString(prefs, prefix, birthdateKey),
      medicalConditions: _readString(prefs, prefix, conditionsKey),
    );

    final client = SupabaseConfig.maybeClient;
    if (isGuest || client == null || user == null) return profile;

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
        firstName: _remoteString(row['first_name']) ?? profile.firstName,
        lastName: _remoteString(row['last_name']) ?? profile.lastName,
        displayName: _remoteString(row['display_name']) ?? profile.displayName,
        email: _remoteString(row['email']) ?? profile.email ?? user.email,
        phone: _remoteString(row['phone']) ?? profile.phone,
        birthdate: _remoteString(row['birthdate']) ?? profile.birthdate,
        medicalConditions:
            _remoteString(row['medical_conditions']) ??
            profile.medicalConditions,
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
    final prefix = await _storagePrefix();
    await prefs.setString(
      _scopedKey(prefix, firstNameKey),
      profile.firstName?.trim() ?? '',
    );
    await prefs.setString(
      _scopedKey(prefix, lastNameKey),
      profile.lastName?.trim() ?? '',
    );
    await prefs.setString(
      _scopedKey(prefix, nameKey),
      profile.resolvedDisplayName ?? '',
    );
    await prefs.setString(
      _scopedKey(prefix, emailKey),
      profile.email?.trim() ?? '',
    );
    await prefs.setString(
      _scopedKey(prefix, phoneKey),
      profile.phone?.trim() ?? '',
    );
    await prefs.setString(
      _scopedKey(prefix, birthdateKey),
      profile.birthdate?.trim() ?? '',
    );
    await prefs.setString(
      _scopedKey(prefix, conditionsKey),
      profile.medicalConditions?.trim() ?? '',
    );

    if (!syncRemote || await _authService.isGuestSession) return;

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

  Future<List<UserEmergencyContact>> loadEmergencyContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = await _storagePrefix();
    final raw = prefs.getString(_scopedKey(prefix, emergencyContactsKey));
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                UserEmergencyContact.fromMap(Map<String, dynamic>.from(item)),
          )
          .where(
            (contact) =>
                contact.name.trim().isNotEmpty &&
                contact.phone.trim().isNotEmpty,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveEmergencyContacts(
    List<UserEmergencyContact> contacts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = await _storagePrefix();
    final encoded = jsonEncode(
      contacts
          .map((contact) => contact.toMap())
          .where(
            (contact) =>
                contact['name']?.trim().isNotEmpty == true &&
                contact['phone']?.trim().isNotEmpty == true,
          )
          .toList(),
    );
    await prefs.setString(_scopedKey(prefix, emergencyContactsKey), encoded);
  }

  Future<String> _storagePrefix() async {
    if (await _authService.isGuestSession) return 'guest';
    return _authService.currentUser?.id ?? 'guest';
  }

  String _scopedKey(String prefix, String key) => 'profile.$prefix.$key';

  String? _readString(SharedPreferences prefs, String prefix, String key) {
    final value = prefs.getString(_scopedKey(prefix, key));
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  String? _remoteString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
