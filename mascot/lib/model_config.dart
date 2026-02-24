import 'dart:io';

import 'toml_parser.dart';

class ModelConfig {
  final String modelDirPath;
  final String modelFile;
  final String? cutinFile;
  final String name;
  final String idleEmotion;
  final double cameraZoom;
  final double cameraY;
  final String mouthParam;
  final double mouthOpenValue;
  final Map<String, double> defaultParameters;
  final Map<String, Map<String, double>> emotionMappings;
  final String fallbackMouthOpen;
  final String fallbackMouthClosed;

  // [cutin] section — cut-in overlay display settings
  final double? cutinZoom;
  final double? cutinCameraY;
  final double? cutinCharWidth;

  const ModelConfig._({
    required this.modelDirPath,
    required this.modelFile,
    this.cutinFile,
    required this.name,
    required this.idleEmotion,
    required this.cameraZoom,
    required this.cameraY,
    required this.mouthParam,
    required this.mouthOpenValue,
    required this.defaultParameters,
    required this.emotionMappings,
    required this.fallbackMouthOpen,
    required this.fallbackMouthClosed,
    this.cutinZoom,
    this.cutinCameraY,
    this.cutinCharWidth,
  });

  /// Load model config from a directory containing `emotions.toml`.
  factory ModelConfig.fromDirectory(String dirPath) {
    final tomlFile = File('$dirPath/emotions.toml');
    if (!tomlFile.existsSync()) {
      throw StateError('emotions.toml not found in $dirPath');
    }
    final toml = TomlParser.parse(tomlFile.readAsStringSync());
    return ModelConfig._fromToml(dirPath, toml);
  }

  /// Load model config from a TOML string (for testing).
  factory ModelConfig.fromTomlString(String dirPath, String tomlSource) {
    final toml = TomlParser.parse(tomlSource);
    return ModelConfig._fromToml(dirPath, toml);
  }

  /// Resolve model from CLI args, env vars, or defaults.
  ///
  /// Priority: CLI arg > env var > default.
  /// Default models dir is `data/models` relative to the exe location.
  factory ModelConfig.fromEnvironment({String? modelsDir, String? model}) {
    final modelName = model
        ?? Platform.environment['MASCOT_MODEL']
        ?? 'blend_shape';
    final baseDir = modelsDir
        ?? Platform.environment['MASCOT_MODELS_DIR']
        ?? _defaultModelsDir();
    final dirPath = '$baseDir/$modelName';
    return ModelConfig.fromDirectory(dirPath);
  }

  /// Resolve default models dir.
  ///
  /// Tries in order:
  /// 1. `data/models` next to the executable (release/distribution builds)
  /// 2. Walk up from exe to find `assets/models` (debug builds via `open -n`)
  /// 3. `assets/models` relative to CWD (debug via `flutter run`)
  static String _defaultModelsDir() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final releaseDir = '$exeDir/data/models';
    if (Directory(releaseDir).existsSync()) return releaseDir;

    // Debug: walk up from exe dir to find project assets
    var dir = Directory(exeDir);
    for (var i = 0; i < 10; i++) {
      dir = dir.parent;
      final candidate = Directory('${dir.path}/assets/models');
      if (candidate.existsSync()) return candidate.path;
    }

    return 'assets/models';
  }

  static ModelConfig _fromToml(String dirPath, Map<String, dynamic> toml) {
    // [model] section
    final model = toml['model'] as Map<String, dynamic>? ?? {};
    final name = (model['name'] as String?) ?? 'Unknown';
    final modelFile = (model['file'] as String?) ?? 'model.inp';
    final cutinFile = model['cutin_file'] as String?;
    final idleEmotion = (model['idle_emotion'] as String?) ?? 'Gentle';

    // [camera] section
    final camera = toml['camera'] as Map<String, dynamic>? ?? {};
    final zoom = _toDouble(camera['zoom']) ?? 0.132;
    final y = _toDouble(camera['y']) ?? -60.0;

    // [mouth] section
    final mouth = toml['mouth'] as Map<String, dynamic>? ?? {};
    final mouthParam = (mouth['param'] as String?) ?? 'MouthOpen';
    final mouthOpenValue = _toDouble(mouth['open_value']) ?? 1.0;

    // [fallback] section
    final fallback = toml['fallback'] as Map<String, dynamic>? ?? {};
    final fallbackMouthOpen = (fallback['mouth_open'] as String?) ??
        'assets/fallback/mouth_open.png';
    final fallbackMouthClosed = (fallback['mouth_closed'] as String?) ??
        'assets/fallback/mouth_closed.png';

    // [cutin] section
    final cutinRaw = toml['cutin'] as Map<String, dynamic>? ?? {};
    final cutinZoom = _toDouble(cutinRaw['zoom']);
    final cutinCameraY = _toDouble(cutinRaw['camera_y']);
    final cutinCharWidth = _toDouble(cutinRaw['char_width']);

    // [defaults] section
    final defaultsRaw = toml['defaults'] as Map<String, dynamic>? ?? {};
    final defaults = <String, double>{};
    for (final entry in defaultsRaw.entries) {
      final v = _toDouble(entry.value);
      if (v != null) defaults[entry.key] = v;
    }

    // [emotions.*] sections
    final emotionsRaw = toml['emotions'] as Map<String, dynamic>? ?? {};
    final emotions = <String, Map<String, double>>{};
    for (final entry in emotionsRaw.entries) {
      final emotionName = entry.key;
      final paramsRaw = entry.value as Map<String, dynamic>? ?? {};
      final params = <String, double>{};
      for (final p in paramsRaw.entries) {
        final v = _toDouble(p.value);
        if (v != null) params[p.key] = v;
      }
      emotions[emotionName] = params;
    }

    return ModelConfig._(
      modelDirPath: dirPath,
      modelFile: modelFile,
      cutinFile: cutinFile,
      name: name,
      idleEmotion: idleEmotion,
      cameraZoom: zoom,
      cameraY: y,
      mouthParam: mouthParam,
      mouthOpenValue: mouthOpenValue,
      defaultParameters: defaults,
      emotionMappings: emotions,
      fallbackMouthOpen: fallbackMouthOpen,
      fallbackMouthClosed: fallbackMouthClosed,
      cutinZoom: cutinZoom,
      cutinCameraY: cutinCameraY,
      cutinCharWidth: cutinCharWidth,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Returns parameter values for the given emotion name.
  /// Returns null if the emotion is unknown.
  Map<String, double>? getEmotionParams(String name) {
    return emotionMappings[name];
  }

  /// Returns the mouth-closed value for the mouth parameter.
  /// Uses the emotion's value for the mouth param, or falls back to defaults.
  double getMouthClosedValue(String? emotion) {
    if (emotion != null) {
      final mapping = emotionMappings[emotion];
      if (mapping != null && mapping.containsKey(mouthParam)) {
        return mapping[mouthParam]!;
      }
    }
    return defaultParameters[mouthParam] ?? 0.0;
  }

  /// Path to the model file in the model directory.
  String get modelFilePath => '$modelDirPath/$modelFile';

  /// Path to the cut-in model file, if configured.
  String? get cutinModelFilePath =>
      cutinFile != null ? '$modelDirPath/$cutinFile' : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelConfig &&
          runtimeType == other.runtimeType &&
          modelDirPath == other.modelDirPath;

  @override
  int get hashCode => modelDirPath.hashCode;

  @override
  String toString() => 'ModelConfig($name, $modelDirPath)';
}
