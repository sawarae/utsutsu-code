import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'mascot_controller.dart';
import 'toml_parser.dart';
import 'tts_service.dart';

/// Coordinates right-click expression: phrase selection, expression display,
/// TTS playback, and cleanup.
class ExpressionService {
  /// Sentinel message shown while Haiku is generating a phrase.
  static const loadingMarker = '\x00loading';
  final MascotController _controller;
  final TtsService _tts = TtsService();
  final Random _random = Random();

  Map<String, List<String>> _phrases = {};
  Map<String, String> _labels = {};
  String? _haikuPromptTemplate;
  bool _busy = false;
  String? _pendingEmotion;

  /// Emotion labels loaded from emotions.toml.
  /// Falls back to emotion keys if labels are not defined.
  Map<String, String> get emotionLabels =>
      _labels.isNotEmpty ? Map.unmodifiable(_labels) : _fallbackLabels;

  static const _fallbackLabels = {
    'Gentle': '穏やか',
    'Joy': '喜び',
    'Blush': '照れ',
    'Trouble': '困惑',
    'Singing': 'ノリノリ',
  };

  /// Hardcoded fallback phrases used when emotions.toml is not found.
  static const _fallbackPhrases = {
    'Gentle': ['元気ですか？', '何かお手伝いしましょうか', 'よろしくお願いします'],
    'Joy': ['やりました！', 'すごいですね！', '成功です！'],
    'Blush': ['えへへ…', 'そろそろ照れますよ…', 'ありがとうございます…'],
    'Trouble': ['うーん、困りました…', 'どうしましょう…', '大丈夫かな…'],
    'Singing': ['ラララ〜♪', 'ルンルン♪', 'いえーい！'],
  };

  ExpressionService(this._controller) {
    _loadConfig();
  }

  void _loadConfig() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir/data/config/emotions.toml',
        '$exeDir/../config/emotions.toml',
        'config/emotions.toml',
      ];

      for (final path in candidates) {
        final file = File(path);
        if (file.existsSync()) {
          final toml = TomlParser.parse(file.readAsStringSync());
          _phrases = _parsePhrases(toml);
          _labels = _parseLabels(toml);
          final haiku = toml['haiku'] as Map<String, dynamic>?;
          if (haiku != null) {
            _haikuPromptTemplate = haiku['prompt'] as String?;
          }
          debugPrint('ExpressionService: loaded config from $path');
          return;
        }
      }
    } catch (e) {
      debugPrint('ExpressionService: failed to load emotions.toml: $e');
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
  /// Shows a static phrase immediately for responsiveness, then generates
  /// a dynamic phrase via Claude Haiku in the background. Once Haiku returns,
  /// the bubble text is swapped and TTS plays the generated phrase.
  /// Falls back to static TOML phrases on Haiku failure.
  /// If already busy, queues one expression to play after the current one.
  Future<void> express(String emotion) async {
    if (_busy) {
      _pendingEmotion = emotion;
      return;
    }
    _busy = true;

    try {
      // Show loading animation immediately
      _controller.showExpression(emotion, loadingMarker);

      // Generate dynamic phrase, fall back to static
      final haikuPhrase = await _generatePhrase(emotion);
      final phrase = haikuPhrase ?? _pickStaticPhrase(emotion);

      // Replace loading with actual text
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

      // Play queued expression if any
      final next = _pendingEmotion;
      _pendingEmotion = null;
      if (next != null) {
        express(next);
      }
    }
  }

  String _pickStaticPhrase(String emotion) {
    final phrases = _phrases[emotion] ?? _fallbackPhrases[emotion] ?? ['…'];
    return phrases[_random.nextInt(phrases.length)];
  }

  /// Generate a phrase using Claude Haiku CLI.
  /// Returns null on failure (CLI not found, timeout, invalid output).
  Future<String?> _generatePhrase(String emotion) async {
    if (_haikuPromptTemplate == null) return null;

    try {
      final prompt = _haikuPromptTemplate!.replaceAll('{emotion}', emotion);
      final result = await Process.run(
        'claude',
        [
          '--model', 'claude-haiku-4-5-20251001',
          '--max-turns', '1',
          '-p',
          prompt,
        ],
        environment: {'PATH': _pathWithLocalBin()},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 10));

      if (result.exitCode != 0) {
        debugPrint('ExpressionService: Haiku CLI failed: ${result.stderr}');
        return null;
      }

      // Take the last non-empty line to skip any preamble
      final lines = (result.stdout as String)
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;

      final output = lines.last.trim();
      if (output.isEmpty || output.length > 100) {
        debugPrint('ExpressionService: Haiku output invalid: "$output"');
        return null;
      }

      debugPrint('ExpressionService: Haiku generated: "$output"');
      return output;
    } catch (e) {
      debugPrint('ExpressionService: Haiku generation failed: $e');
      return null;
    }
  }

  /// Ensure ~/.local/bin is in PATH for the claude CLI.
  static String _pathWithLocalBin() {
    final path = Platform.environment['PATH'] ?? '';
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      return '$home/.local/bin:$path';
    }
    return path;
  }

  void dispose() {
    _tts.dispose();
  }
}
