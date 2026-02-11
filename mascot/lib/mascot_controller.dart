import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_config.dart';

class MascotController extends ChangeNotifier {
  final String _signalPath;
  final String _listeningPath;
  late final ModelConfig _modelConfig;

  bool _isSpeaking = false;
  bool _isListening = false;
  String _message = '';
  String? _currentEmotion;

  late final Map<String, double> _parameters;

  Timer? _pollTimer;
  Timer? _animTimer;

  /// The model configuration for this controller.
  ModelConfig get modelConfig => _modelConfig;

  /// Unmodifiable view of the current parameter values.
  Map<String, double> get parameters => Map.unmodifiable(_parameters);

  /// Backward-compatible getter: true when mouth param > 0.5.
  bool get showOpenMouth => _parameters[_modelConfig.mouthParam]! > 0.5;

  String get message => _message;
  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;

  MascotController({String? signalDir, String? modelsDir, String? model})
      : this._fromDir(signalDir ?? _defaultSignalDir(),
            modelsDir: modelsDir, model: model);

  MascotController._fromDir(String dir, {String? modelsDir, String? model})
      : _signalPath = '$dir/mascot_speaking',
        _listeningPath = '$dir/mascot_listening' {
    _modelConfig = ModelConfig.fromEnvironment(
      modelsDir: modelsDir,
      model: model,
    );
    _parameters = Map<String, double>.from(_modelConfig.defaultParameters);
    _setEmotion(null); // Apply idle emotion
    _startPolling();
  }

  @visibleForTesting
  MascotController.withConfig(this._signalPath, ModelConfig config)
      : _listeningPath = '${File(_signalPath).parent.path}/mascot_listening' {
    _modelConfig = config;
    _parameters = Map<String, double>.from(_modelConfig.defaultParameters);
    _setEmotion(null); // Apply idle emotion
    _startPolling();
  }

  static String _defaultSignalDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) {
      throw StateError('HOME/USERPROFILE environment variable not set');
    }
    final dir = '$home/.claude/utsutsu-code';
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _checkSignalFile(),
    );
  }

  void _checkSignalFile() {
    final file = File(_signalPath);
    final speaking = file.existsSync();
    if (speaking && !_isSpeaking) {
      _isSpeaking = true;
      try {
        final content = file.readAsStringSync().trim();
        _parseSignalContent(content);
      } catch (_) {
        _message = '';
        _setEmotion(null);
      }
      _startMouthAnimation();
    } else if (!speaking && _isSpeaking) {
      _isSpeaking = false;
      _stopMouthAnimation();
      _setEmotion(null);
    }

    // Check listening signal file
    final listeningFile = File(_listeningPath);
    final listening = listeningFile.existsSync();
    if (listening != _isListening) {
      _isListening = listening;
      if (listening && !_isSpeaking) {
        _setEmotion(_modelConfig.idleEmotion);
      } else if (!listening && !_isSpeaking) {
        _setEmotion(null);
      }
      notifyListeners();
    }
  }

  /// Parse signal file content.
  ///
  /// Supports two formats:
  /// - JSON: `{"message": "text", "emotion": "Joy"}`
  /// - Plain text: `text` (backward compatible, no emotion)
  void _parseSignalContent(String content) {
    if (content.isEmpty) {
      _message = '';
      _setEmotion(null);
      return;
    }

    // Try JSON first
    if (content.startsWith('{')) {
      try {
        final json = jsonDecode(content) as Map<String, dynamic>;
        _message = (json['message'] as String?) ?? '';
        final emotion = json['emotion'] as String?;
        _setEmotion(emotion);
        return;
      } on FormatException {
        // Not valid JSON, fall through to plain text
      }
    }

    // Plain text fallback
    _message = content;
    _setEmotion(null);
  }

  /// Apply emotion parameters from the model config.
  /// Pass null to reset to idle emotion (from config's idle_emotion).
  void _setEmotion(String? name) {
    _currentEmotion = name;

    final effectiveName = name ?? _modelConfig.idleEmotion;
    final mapping = _modelConfig.getEmotionParams(effectiveName);

    if (mapping != null) {
      // Apply all default parameters first, then overlay the emotion
      for (final entry in _modelConfig.defaultParameters.entries) {
        _parameters[entry.key] = entry.value;
      }
      for (final entry in mapping.entries) {
        _parameters[entry.key] = entry.value;
      }
    } else {
      // Unknown emotion or no idle — reset to defaults
      for (final entry in _modelConfig.defaultParameters.entries) {
        _parameters[entry.key] = entry.value;
      }
    }
  }

  void _startMouthAnimation() {
    _animTimer?.cancel();
    _animTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) {
        final current = _parameters[_modelConfig.mouthParam]!;
        final closedValue = _modelConfig.getMouthClosedValue(_currentEmotion);
        final openValue = _modelConfig.mouthOpenValue;
        _parameters[_modelConfig.mouthParam] =
            (current - closedValue).abs() < 0.01 ? openValue : closedValue;
        notifyListeners();
      },
    );
  }

  void _stopMouthAnimation() {
    _animTimer?.cancel();
    _animTimer = null;
    _parameters[_modelConfig.mouthParam] =
        _modelConfig.getMouthClosedValue(_currentEmotion);
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _animTimer?.cancel();
    _cleanup();
    super.dispose();
  }

  /// Remove stale signal files on shutdown.
  void _cleanup() {
    for (final path in [_signalPath, _listeningPath]) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }
}
