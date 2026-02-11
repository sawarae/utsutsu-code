import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'mascot_controller.dart';
import 'toml_parser.dart';
import 'tts_service.dart';

/// A single speech bubble managed by [ExpressionService].
class BubbleEntry {
  final int id;
  String text;
  BubbleEntry(this.id, this.text);
}

/// Coordinates right-click expression: phrase generation, bubble management,
/// TTS playback, and cleanup.
///
/// Extends [ChangeNotifier] so the widget can listen for bubble changes.
/// Supports up to [maxBubbles] concurrent bubbles.
class ExpressionService extends ChangeNotifier {
  /// Sentinel message shown while Haiku is generating a phrase.
  static const loadingMarker = '\x00loading';

  /// Maximum number of concurrent bubbles.
  static const maxBubbles = 2;

  final MascotController _controller;
  final TtsService _tts = TtsService();
  final Random _random = Random();

  Map<String, List<String>> _phrases = {};
  Map<String, String> _labels = {};
  String? _haikuPromptTemplate;

  /// Currently active speech bubbles.
  final List<BubbleEntry> activeBubbles = [];
  int _nextBubbleId = 0;

  /// Emotion labels loaded from emotions.toml.
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

  /// Trigger an expression with a concurrent bubble.
  ///
  /// Each call creates an independent bubble that generates a phrase via
  /// Claude Haiku, plays TTS, then removes itself. Up to [maxBubbles]
  /// bubbles can be active simultaneously. The face expression updates
  /// to the latest emotion.
  Future<void> express(String emotion) async {
    if (activeBubbles.length >= maxBubbles) return;

    final id = _nextBubbleId++;
    final entry = BubbleEntry(id, loadingMarker);
    activeBubbles.add(entry);
    notifyListeners();

    // Update face expression to latest emotion
    _controller.showExpression(emotion, '');

    try {
      // Generate dynamic phrase, fall back to static
      final haikuPhrase = await _generatePhrase(emotion);
      final phrase = haikuPhrase ?? _pickStaticPhrase(emotion);

      entry.text = phrase;
      notifyListeners();

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
      activeBubbles.removeWhere((b) => b.id == id);
      notifyListeners();

      if (activeBubbles.isEmpty) {
        _controller.hideExpression();
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

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }
}
