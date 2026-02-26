import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// COEIROINK v2 API client for text-to-speech synthesis.
///
/// Uses only [dart:io] HttpClient — no external packages required.
/// Gracefully degrades: if COEIROINK is not running, [isAvailable] returns
/// false and [synthesizeAndPlay] is a no-op.
class TtsService {
  static const _port = 50032;
  static const _baseUrl = 'http://localhost:$_port';
  static const _availabilityTimeout = Duration(seconds: 1);
  static const _synthesisTimeout = Duration(seconds: 4);

  final HttpClient _client = HttpClient();

  /// Cached speaker info after first successful lookup.
  String? _speakerUuid;
  int? _styleId;

  TtsService() {
    _client.connectionTimeout = _availabilityTimeout;
  }

  /// Check whether COEIROINK v2 is running and reachable.
  Future<bool> isAvailable() async {
    try {
      final request = await _client
          .getUrl(Uri.parse('$_baseUrl/v1/speakers'))
          .timeout(_availabilityTimeout);
      final response = await request.close().timeout(_availabilityTimeout);
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Find and cache the first available speaker.
  Future<bool> _ensureSpeaker() async {
    if (_speakerUuid != null && _styleId != null) return true;

    try {
      final request = await _client
          .getUrl(Uri.parse('$_baseUrl/v1/speakers'))
          .timeout(_availabilityTimeout);
      final response = await request.close().timeout(_availabilityTimeout);
      final body = await response.transform(utf8.decoder).join();
      final speakers = jsonDecode(body) as List<dynamic>;

      for (final speaker in speakers) {
        final styles = speaker['styles'] as List<dynamic>?;
        if (styles != null && styles.isNotEmpty) {
          _speakerUuid = speaker['speakerUuid'] as String;
          _styleId = styles[0]['styleId'] as int;
          return true;
        }
      }
    } catch (e) {
      debugPrint('TtsService: speaker lookup failed: $e');
    }
    return false;
  }

  /// Synthesize speech and play it. Calls [onComplete] when playback finishes.
  ///
  /// Returns immediately if COEIROINK is unavailable. Does not throw.
  Future<void> synthesizeAndPlay(String text,
      {VoidCallback? onComplete}) async {
    try {
      if (!await _ensureSpeaker()) {
        onComplete?.call();
        return;
      }

      // Step 1: Estimate prosody
      final prosody = await _postJson(
        '/v1/estimate_prosody',
        {'text': text},
      );
      if (prosody == null) {
        onComplete?.call();
        return;
      }

      // Step 2: Predict (generate WAV)
      final predictBody = {
        'speakerUuid': _speakerUuid,
        'styleId': _styleId,
        'text': text,
        'prosodyDetail': prosody['detail'],
        'speedScale': 1.0,
      };
      final wavBytes = await _postBinary('/v1/predict', predictBody);
      if (wavBytes == null) {
        onComplete?.call();
        return;
      }

      // Step 3: Write WAV to temp file and play
      final tempFile = File(
          '${Directory.systemTemp.path}/mascot_tts_${DateTime.now().millisecondsSinceEpoch}.wav');
      await tempFile.writeAsBytes(wavBytes);

      try {
        await _playWav(tempFile.path);
      } finally {
        try {
          await tempFile.delete();
        } catch (_) {}
        onComplete?.call();
      }
    } catch (e) {
      debugPrint('TtsService: synthesis failed: $e');
      onComplete?.call();
    }
  }

  /// POST JSON and return decoded response body.
  Future<Map<String, dynamic>?> _postJson(
      String path, Map<String, dynamic> body) async {
    try {
      final request = await _client
          .postUrl(Uri.parse('$_baseUrl$path'))
          .timeout(_synthesisTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(_synthesisTimeout);
      final responseBody = await response.transform(utf8.decoder).join();
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('TtsService: POST $path failed: $e');
      return null;
    }
  }

  /// POST JSON and return raw response bytes (for WAV data).
  Future<List<int>?> _postBinary(
      String path, Map<String, dynamic> body) async {
    try {
      final request = await _client
          .postUrl(Uri.parse('$_baseUrl$path'))
          .timeout(_synthesisTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(_synthesisTimeout);
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return bytes;
    } catch (e) {
      debugPrint('TtsService: POST $path (binary) failed: $e');
      return null;
    }
  }

  /// Play a WAV file using the platform's native player.
  Future<void> _playWav(String path) async {
    if (Platform.isMacOS) {
      await Process.run('afplay', [path]);
    } else if (Platform.isWindows) {
      // Use environment variable to avoid PowerShell injection via path.
      await Process.run('powershell', [
        '-c',
        r"(New-Object System.Media.SoundPlayer($env:MASCOT_WAV)).PlaySync()",
      ], environment: {'MASCOT_WAV': path});
    } else {
      // Linux: use aplay (requires alsa-utils package)
      final result = await Process.run('aplay', [path]);
      if (result.exitCode != 0) {
        debugPrint('Failed to play audio with aplay: ${result.stderr}');
        debugPrint('Ensure alsa-utils is installed: sudo apt-get install alsa-utils');
      }
    }
  }

  void dispose() {
    _client.close(force: true);
  }
}
