import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:lifeease/core/constants/env_config.dart';

class GroqTranscription {
  final String text;
  final String model;

  const GroqTranscription({required this.text, required this.model});
}

class GroqTranscriptionException implements Exception {
  final String message;

  const GroqTranscriptionException(this.message);

  @override
  String toString() => message;
}

class GroqService {
  GroqService({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _transcriptionsUri = Uri.parse(
    'https://api.groq.com/openai/v1/audio/transcriptions',
  );

  final http.Client _client;

  bool get isConfigured {
    final key = EnvConfig.groqApiKey;
    return !EnvConfig.isPlaceholder(key);
  }

  Future<GroqTranscription> transcribeFile({
    required File audioFile,
    String model = 'whisper-large-v3',
    Duration timeout = const Duration(seconds: 45),
  }) {
    return _sendMultipart(
      model: model,
      timeout: timeout,
      file: http.MultipartFile.fromPath('file', audioFile.path),
    );
  }

  Future<GroqTranscription> transcribeBytes({
    required Uint8List audioBytes,
    required String fileName,
    String model = 'whisper-large-v3',
    Duration timeout = const Duration(seconds: 45),
  }) {
    return _sendMultipart(
      model: model,
      timeout: timeout,
      file: Future.value(
        http.MultipartFile.fromBytes('file', audioBytes, filename: fileName),
      ),
    );
  }

  Future<GroqTranscription> _sendMultipart({
    required String model,
    required Duration timeout,
    required Future<http.MultipartFile> file,
  }) async {
    final key = EnvConfig.groqApiKey;
    if (EnvConfig.isPlaceholder(key)) {
      throw const GroqTranscriptionException('Groq API key is not configured.');
    }

    try {
      final request = http.MultipartRequest('POST', _transcriptionsUri)
        ..headers['Authorization'] = 'Bearer $key'
        ..fields['model'] = model
        ..fields['response_format'] = 'json'
        ..fields['temperature'] = '0'
        ..fields['prompt'] =
            'Transcribe clearly. The speaker may use English, Tagalog, or Taglish.';

      request.files.add(await file);

      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GroqTranscriptionException(
          _messageForStatus(response.statusCode),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GroqTranscriptionException(
          'Groq returned an invalid response.',
        );
      }

      final text = decoded['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        throw const GroqTranscriptionException(
          'No transcription was returned. Please try speaking again.',
        );
      }

      return GroqTranscription(text: text, model: model);
    } on SocketException {
      throw const GroqTranscriptionException(
        'No internet connection. Please check your network and try again.',
      );
    } on TimeoutException {
      throw const GroqTranscriptionException(
        'Groq transcription timed out. Please try again.',
      );
    } on FormatException {
      throw const GroqTranscriptionException(
        'Groq returned an invalid response.',
      );
    } on GroqTranscriptionException {
      rethrow;
    } catch (_) {
      throw const GroqTranscriptionException(
        'Unable to transcribe audio right now. Please try again.',
      );
    }
  }

  String _messageForStatus(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return 'Groq API key is invalid or unauthorized.';
    }
    if (statusCode == 413) {
      return 'Audio file is too large for Groq transcription.';
    }
    if (statusCode == 429) {
      return 'Groq rate limit reached. Please try again shortly.';
    }
    if (statusCode >= 500) {
      return 'Groq service is temporarily unavailable. Please try again.';
    }
    return 'Groq transcription failed. Please try again.';
  }
}
