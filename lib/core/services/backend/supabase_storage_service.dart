import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifeease/core/services/supabase_config.dart';

class SupabaseStorageService {
  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  Future<String?> uploadAudio({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return null;
    final path = '$userId/$fileName';
    await client.storage.from('audio-recordings').uploadBinary(path, bytes);
    return path;
  }

  Future<String?> uploadProfileImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return null;
    final path = '$userId/$fileName';
    await client.storage.from('profile-images').uploadBinary(path, bytes);
    return client.storage.from('profile-images').getPublicUrl(path);
  }
}
