import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'mascot_controller.dart';
import 'toml_parser.dart';
import 'tts_service.dart';

/// Coordinates right-click expression: phrase selection, expression display,
/// TTS playback, and cleanup.
class ExpressionService {
  final MascotController _controller;
  final TtsService _tts = TtsService();
  final Random _random = Random();

  Map<String, List<String>> _phrases = {};
  Map<String, String> _labels = {};
  bool _busy = false;

  /// Emotion labels for the right-click menu, loaded from expressions.toml.
  /// Falls back to emotion keys if labels are not defined.
  Map<String, String> get emotionLabels =>
      _labels.isNotEmpty ? Map.unmodifiable(_labels) : _fallbackLabels;

  /// Hardcoded fallback labels used when expressions.toml has no label fields.
  static const _fallbackLabels = {
    'Gentle': '穏やか',
    'Joy': '喜び',
    'Blush': '照れ',
    'Trouble': '困惑',
    'Singing': 'ノリノリ',
  };

  /// Hardcoded fallback phrases used when expressions.toml is not found.
  static const _fallbackPhrases = {
    'Gentle': ['元気ですか？', '何かお手伝いしましょうか', 'よろしくお願いします'],
    'Joy': ['やりました！', 'すごいですね！', '成功です！'],
    'Blush': ['えへへ…', 'そろそろ照れますよ…', 'ありがとうございます…'],
    'Trouble': ['うーん、困りました…', 'どうしましょう…', '大丈夫かな…'],
    'Singing': ['ラララ〜♪', 'ルンルン♪', 'いえーい！'],
  };

  ExpressionService(this._controller) {
    _loadPhrases();
  }

  void _loadPhrases() {
    try {
      // Try loading from config/expressions.toml relative to the executable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir/data/config/expressions.toml',
        '$exeDir/../config/expressions.toml',
        'config/expressions.toml',
      ];

      for (final path in candidates) {
        final file = File(path);
        if (file.existsSync()) {
          final toml = TomlParser.parse(file.readAsStringSync());
          _phrases = _parsePhrases(toml);
          _labels = _parseLabels(toml);
          debugPrint('ExpressionService: loaded phrases from $path');
          return;
        }
      }
    } catch (e) {
      debugPrint('ExpressionService: failed to load expressions.toml: $e');
    }

    // Use hardcoded fallback
    _phrases = {
      for (final entry in _fallbackPhrases.entries)
        entry.key: List<String>.from(entry.value),
    };
    debugPrint('ExpressionService: using fallback phrases');
  }

  Map<String, String> _parseLabels(Map<String, dynamic> toml) {
    final result = <String, String>{};
    for (final entry in toml.entries) {
      final section = entry.value;
      if (section is Map<String, dynamic>) {
        final label = section['label'];
        if (label is String) {
          result[entry.key] = label;
        }
      }
    }
    return result;
  }

  Map<String, List<String>> _parsePhrases(Map<String, dynamic> toml) {
    final result = <String, List<String>>{};
    for (final entry in toml.entries) {
      final section = entry.value;
      if (section is Map<String, dynamic>) {
        final phrases = section['phrases'];
        if (phrases is List) {
          result[entry.key] = phrases.cast<String>();
        }
      }
    }
    return result;
  }

  /// Trigger a random emotion expression.
  Future<void> expressRandom() async {
    final emotions = _phrases.keys.toList();
    if (emotions.isEmpty) return;
    final emotion = emotions[_random.nextInt(emotions.length)];
    await express(emotion);
  }

  /// Trigger an expression: show emotion + phrase, play TTS, then reset.
  ///
  /// If already busy (another expression is playing), this is a no-op.
  Future<void> express(String emotion) async {
    if (_busy) return;
    _busy = true;

    try {
      final phrases = _phrases[emotion] ?? _fallbackPhrases[emotion] ?? ['…'];
      final phrase = phrases[_random.nextInt(phrases.length)];

      _controller.showExpression(emotion, phrase);

      // Try TTS; if unavailable, show expression for a fixed duration
      final available = await _tts.isAvailable();
      if (available) {
        await _tts.synthesizeAndPlay(phrase);
        // Linger after TTS so the bubble doesn't vanish instantly
        await Future<void>.delayed(const Duration(seconds: 4));
      } else {
        // No TTS: show expression for 6 seconds
        await Future<void>.delayed(const Duration(seconds: 6));
      }
    } finally {
      _controller.hideExpression();
      _busy = false;
    }
  }

  void dispose() {
    _tts.dispose();
  }
}
