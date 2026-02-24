import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:utsutsu2d/utsutsu2d.dart';

import '../model_config.dart';

/// Pre-renders puppet model frames as cached [ui.Image] for batch drawing.
///
/// Renders at 2x resolution for Retina displays. Captures the puppet in
/// different states (emotion × facing × mouth) so the [SwarmPainter] can
/// draw sprites with a single `canvas.drawImage()`.
class SpriteCache {
  final Map<String, ui.Image> _cache = {};

  /// Logical size of each sprite (used for layout).
  double spriteWidth = 0;
  double spriteHeight = 0;

  /// Pixel size of each sprite (2x for Retina).
  int pixelWidth = 0;
  int pixelHeight = 0;

  /// Scale factor (pixel / logical).
  static const double scale = 2.0;

  /// Whether the cache has been populated.
  bool get isReady => _cache.isNotEmpty;

  /// Get a cached sprite frame.
  ///
  /// Key format: "{emotion}_{arm}_{facing}_{mouth}".
  /// Falls back to idle emotion if the requested emotion is not cached.
  ui.Image? getFrame(
    bool facingLeft,
    bool mouthOpen,
    String? emotion, {
    String armState = 'luggage',
  }) {
    final facing = facingLeft ? 'left' : 'right';
    final mouth = mouthOpen ? 'open' : 'closed';
    final emotionKey = emotion ?? '_idle';
    final key = '${emotionKey}_${armState}_${facing}_$mouth';
    return _cache[key] ?? _cache['_idle_${armState}_${facing}_$mouth'];
  }

  /// Pre-render all sprite frames from the puppet model.
  ///
  /// Creates frames for each emotion × facing × mouth state.
  /// Renders at 2x resolution for Retina sharpness.
  Future<void> prebake(ModelConfig config, double width, double height) async {
    spriteWidth = width;
    spriteHeight = height;
    pixelWidth = (width * scale).toInt();
    pixelHeight = (height * scale).toInt();

    // Load model
    final file = File(config.modelFilePath);
    if (!file.existsSync()) {
      debugPrint('SpriteCache: model file not found: ${config.modelFilePath}');
      return;
    }

    final bytes = file.readAsBytesSync();
    final fileName = p.basename(config.modelFilePath);
    final model = ModelLoader.loadFromBytes(bytes, fileName);

    // Decode textures
    final textures = <ui.Image>[];
    for (final texture in model.textures) {
      final codec = await ui.instantiateImageCodec(texture.data);
      final frame = await codec.getNextFrame();
      textures.add(frame.image);
    }

    // Create PuppetController and configure camera for 2x render size
    final pc = PuppetController();
    await pc.loadModel(model, textures);

    // Set DPR for PSD compositor offscreen buffers (Retina 2x)
    pc.renderer?.devicePixelRatio = scale;

    final camera = pc.camera;
    if (camera != null) {
      camera.zoom = config.cameraZoom * (width / 264.0);
      camera.position = Vec2(0, config.cameraY);
    }

    final puppet = pc.puppet;
    final renderer = pc.renderer;
    if (puppet == null || renderer == null) {
      debugPrint('SpriteCache: failed to load puppet');
      pc.dispose();
      return;
    }

    // Collect all emotions to prebake
    final emotions = <String?>[null]; // null = idle
    for (final emotionName in config.emotionMappings.keys) {
      emotions.add(emotionName);
    }

    // Arm state parameter sets
    const armStates = <String, Map<String, double>>{
      'luggage': {'Arm_Empty': 0, 'Arm_Broom': 0, 'Arm_Luggage': 1},
      'broom': {'Arm_Empty': 0, 'Arm_Broom': 1, 'Arm_Luggage': 0},
      'empty': {'Arm_Empty': 1, 'Arm_Broom': 0, 'Arm_Luggage': 0},
    };

    for (final emotion in emotions) {
      final emotionKey = emotion ?? '_idle';

      for (final armEntry in armStates.entries) {
        // Apply default parameters
        for (final entry in config.defaultParameters.entries) {
          puppet.setParam(entry.key, entry.value);
        }

        // Apply emotion (or idle)
        final emotionName = emotion ?? config.idleEmotion;
        final emotionParams = config.getEmotionParams(emotionName);
        if (emotionParams != null) {
          for (final entry in emotionParams.entries) {
            puppet.setParam(entry.key, entry.value);
          }
        }

        // Apply arm state
        for (final armParam in armEntry.value.entries) {
          puppet.setParam(armParam.key, armParam.value);
        }

        for (final facingLeft in [true, false]) {
          for (final mouthOpen in [true, false]) {
            final mouthValue = mouthOpen
                ? config.mouthOpenValue
                : config.getMouthClosedValue(emotion);
            puppet.setParam(config.mouthParam, mouthValue);
            pc.updateManual();

            final image = _captureFrame(renderer, puppet, facingLeft);
            final facing = facingLeft ? 'left' : 'right';
            final mouth = mouthOpen ? 'open' : 'closed';
            _cache['${emotionKey}_${armEntry.key}_${facing}_$mouth'] = image;
          }
        }
      }
    }

    pc.dispose();
    debugPrint(
      'SpriteCache: prebaked ${_cache.length} frames '
      '(${pixelWidth}x$pixelHeight px, ${width.toInt()}x${height.toInt()} logical)',
    );
  }

  ui.Image _captureFrame(
    CanvasRenderer renderer,
    Puppet puppet,
    bool facingLeft,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Render at 2x scale for Retina
    canvas.scale(scale, scale);
    final size = ui.Size(spriteWidth, spriteHeight);

    if (!facingLeft) {
      canvas.translate(spriteWidth, 0);
      canvas.scale(-1, 1);
    }

    renderer.render(canvas, size, puppet);

    final picture = recorder.endRecording();
    final image = picture.toImageSync(pixelWidth, pixelHeight);
    picture.dispose();
    return image;
  }

  void dispose() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }
}
