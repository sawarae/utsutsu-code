import 'dart:io' show File, Directory, Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:utsutsu2d/utsutsu2d.dart';

import '../model_config.dart';

/// Pre-renders puppet model frames as cached [ui.Image] for batch drawing.
///
/// Captures the puppet in different states (facing, mouth open/closed, emotions)
/// so the [SwarmPainter] can draw sprites with a single `canvas.drawImage()`.
class SpriteCache {
  final Map<String, ui.Image> _cache = {};
  double spriteWidth = 0;
  double spriteHeight = 0;

  /// Whether the cache has been populated.
  bool get isReady => _cache.isNotEmpty;

  /// Get a cached sprite frame.
  ///
  /// Key format: "{facing}_{mouth}" where facing is "left"/"right"
  /// and mouth is "closed"/"open".
  ui.Image? getFrame(bool facingLeft, bool mouthOpen) {
    final facing = facingLeft ? 'left' : 'right';
    final mouth = mouthOpen ? 'open' : 'closed';
    return _cache['${facing}_$mouth'];
  }

  /// Pre-render all sprite frames from the puppet model.
  ///
  /// Creates 4 frames: left_closed, left_open, right_closed, right_open.
  Future<void> prebake(ModelConfig config, double width, double height) async {
    spriteWidth = width;
    spriteHeight = height;

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

    // Create PuppetController and configure camera for wander size
    final pc = PuppetController();
    await pc.loadModel(model, textures);
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

    // Apply default parameters
    for (final entry in config.defaultParameters.entries) {
      puppet.setParam(entry.key, entry.value);
    }
    // Apply idle emotion
    final idleParams = config.getEmotionParams(config.idleEmotion);
    if (idleParams != null) {
      for (final entry in idleParams.entries) {
        puppet.setParam(entry.key, entry.value);
      }
    }

    // Render 4 frames: (facingLeft, mouthOpen)
    for (final facingLeft in [true, false]) {
      for (final mouthOpen in [true, false]) {
        // Set mouth state
        final mouthValue = mouthOpen ? config.mouthOpenValue : config.getMouthClosedValue(null);
        puppet.setParam(config.mouthParam, mouthValue);
        pc.updateManual();

        final image = _captureFrame(renderer, puppet, width, height, facingLeft);
        final facing = facingLeft ? 'left' : 'right';
        final mouth = mouthOpen ? 'open' : 'closed';
        _cache['${facing}_$mouth'] = image;
      }
    }

    pc.dispose();
    debugPrint('SpriteCache: prebaked ${_cache.length} frames (${width.toInt()}x${height.toInt()})');
  }

  ui.Image _captureFrame(
    CanvasRenderer renderer,
    Puppet puppet,
    double width,
    double height,
    bool facingLeft,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(width, height);

    if (!facingLeft) {
      // Flip horizontally: translate to width, scale x by -1
      canvas.translate(width, 0);
      canvas.scale(-1, 1);
    }

    renderer.render(canvas, size, puppet);

    final picture = recorder.endRecording();
    final image = picture.toImageSync(width.toInt(), height.toInt());
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
