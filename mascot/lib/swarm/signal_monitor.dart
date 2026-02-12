import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'mascot_entity.dart';

/// Centralized signal file scanner for all swarm entities.
///
/// One timer scans all entity signal directories, handling TTS signals
/// and dismiss commands. Replaces per-entity MascotController polling.
class SignalMonitor {
  Timer? _timer;
  final int pollIntervalMs;

  /// Minimum duration (ms) to keep a speech bubble visible, even if the
  /// signal file is deleted sooner (e.g. mascot_tts.py clears it after audio).
  final int minBubbleDurationMs;

  /// Called when an entity should show a speech bubble.
  final void Function(MascotEntity entity, String message, String? emotion)? onSpeech;

  /// Called when an entity's speech ends.
  final void Function(MascotEntity entity)? onSpeechEnd;

  /// Called when an entity should be dismissed.
  final void Function(MascotEntity entity)? onDismiss;

  SignalMonitor({
    this.pollIntervalMs = 200,
    this.minBubbleDurationMs = 5000,
    this.onSpeech,
    this.onSpeechEnd,
    this.onDismiss,
  });

  void start(List<MascotEntity> entities) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: pollIntervalMs),
      (_) => _scan(entities),
    );
  }

  void _scan(List<MascotEntity> entities) {
    for (final e in entities) {
      if (e.dismissed) continue;
      _checkTts(e);
      _checkDismiss(e);
    }
  }

  void _checkTts(MascotEntity e) {
    final file = File('${e.signalDir}/mascot_speaking');
    final exists = file.existsSync();

    if (exists && !e.isSpeaking) {
      e.isSpeaking = true;
      e.speakingStartMs = DateTime.now().millisecondsSinceEpoch;
      try {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final parsed = _parseSignalContent(content);
          e.message = parsed.$1;
          e.emotion = parsed.$2;
          onSpeech?.call(e, parsed.$1, parsed.$2);
        }
      } catch (_) {
        e.message = '';
        e.emotion = null;
      }
    } else if (!exists && e.isSpeaking) {
      // Keep the bubble visible for at least minBubbleDurationMs so users
      // can read it, even when mascot_tts.py deletes the file early.
      final elapsed =
          DateTime.now().millisecondsSinceEpoch - e.speakingStartMs;
      if (elapsed >= minBubbleDurationMs) {
        e.isSpeaking = false;
        e.message = '';
        e.emotion = null;
        onSpeechEnd?.call(e);
      }
    }
  }

  void _checkDismiss(MascotEntity e) {
    final file = File('${e.signalDir}/mascot_dismiss');
    if (file.existsSync()) {
      e.dismissed = true;
      onDismiss?.call(e);
    }
  }

  /// Parse signal file content, supporting envelope v1, legacy JSON, and plain text.
  (String message, String? emotion) _parseSignalContent(String content) {
    if (content.startsWith('{')) {
      try {
        final json = jsonDecode(content) as Map<String, dynamic>;
        final payload = json.containsKey('version')
            ? (json['payload'] as Map<String, dynamic>? ?? {})
            : json;
        final message = (payload['message'] as String?) ?? '';
        final emotion = payload['emotion'] as String?;
        return (message, emotion);
      } on FormatException {
        // Not valid JSON, fall through
      }
    }
    return (content, null);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
