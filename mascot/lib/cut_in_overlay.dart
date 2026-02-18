import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:utsutsu2d/utsutsu2d.dart' hide Animation;

import 'mascot_controller.dart';
import 'tts_service.dart';

/// Available cut-in background patterns.
///
/// Each entry maps to an SVG file in `assets/backgrounds/`.
enum CutInBackground {
  speedLines('speed_lines'),
  diagonalStripes('diagonal_stripes'),
  sparkleBurst('sparkle_burst'),
  sakura('sakura'),
  cyber('cyber');

  final String fileName;
  const CutInBackground(this.fileName);

  String get assetPath => 'assets/backgrounds/$fileName.svg';

  /// Pick a background based on emotion.
  static CutInBackground forEmotion(String? emotion) {
    return switch (emotion) {
      'Joy' => CutInBackground.sparkleBurst,
      'Singing' => CutInBackground.sparkleBurst,
      'Blush' => CutInBackground.sakura,
      'Trouble' => CutInBackground.diagonalStripes,
      'Gentle' => CutInBackground.sakura,
      _ => CutInBackground.speedLines,
    };
  }

  static CutInBackground? fromName(String? name) {
    if (name == null) return null;
    for (final bg in values) {
      if (bg.fileName == name || bg.name == name) return bg;
    }
    return null;
  }
}

/// Full-screen cut-in overlay — social-game style dramatic animation.
///
/// Shows a background SVG, the character standing illustration, and
/// styled dialogue text with a slide-in/out animation sequence.
class CutInOverlay extends StatefulWidget {
  final String message;
  final String emotion;
  final CutInBackground background;
  final MascotController controller;

  /// Called when the cut-in animation finishes (including exit).
  final VoidCallback? onComplete;

  const CutInOverlay({
    super.key,
    required this.message,
    required this.emotion,
    required this.background,
    required this.controller,
    this.onComplete,
  });

  @override
  State<CutInOverlay> createState() => _CutInOverlayState();
}

class _CutInOverlayState extends State<CutInOverlay>
    with TickerProviderStateMixin {
  // Phase 1: Background slides in from right (0.0 → 1.0)
  late final AnimationController _bgController;
  late final Animation<Offset> _bgSlide;

  // Phase 2: Character slides in from left (0.0 → 1.0)
  late final AnimationController _charController;
  late final Animation<Offset> _charSlide;

  // Phase 3: Text fades in
  late final AnimationController _textController;

  // Phase 4: Everything slides out to left
  late final AnimationController _exitController;
  late final Animation<Offset> _exitSlide;

  // Flash overlay for dramatic entrance
  late final AnimationController _flashController;

  static const _windowReadyChannel = MethodChannel('mascot/window_ready');

  PuppetController? _puppetController;
  bool _modelLoaded = false;
  final Completer<void> _modelReady = Completer<void>();
  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();

    // Background: slide in from right
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _bgSlide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeOutCubic));

    // Character: slide in from left with slight overshoot
    _charController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _charSlide = Tween<Offset>(
      begin: const Offset(-1.5, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _charController, curve: Curves.easeOutBack));

    // Text: fade in
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Exit: everything slides out to left
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _exitSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.2, 0.0),
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic));

    // Flash: white flash on entrance
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _loadModel();
    _startSequence();
  }

  Future<void> _loadModel() async {
    try {
      final config = widget.controller.modelConfig;
      final file = io.File(config.modelFilePath);
      if (!file.existsSync()) return;

      final bytes = file.readAsBytesSync();
      final fileName = p.basename(config.modelFilePath);
      final model = ModelLoader.loadFromBytes(bytes, fileName);

      final textures = <ui.Image>[];
      for (final texture in model.textures) {
        final codec = await ui.instantiateImageCodec(texture.data);
        final frame = await codec.getNextFrame();
        textures.add(frame.image);
      }

      final pc = PuppetController();
      await pc.loadModel(model, textures);

      // Set camera for a large, dramatic cut-in pose (shifted down)
      final camera = pc.camera;
      if (camera != null) {
        camera.zoom = config.cameraZoom * 2.5;
        camera.position = Vec2(0, config.cameraY * 0.8 - 650);
      }

      // Apply emotion parameters
      final puppet = pc.puppet;
      if (puppet != null) {
        final params = widget.controller.parameters;
        for (final entry in params.entries) {
          puppet.setParam(entry.key, entry.value);
        }
        pc.updateManual();
      }

      if (mounted) {
        setState(() {
          _puppetController = pc;
          _modelLoaded = true;
        });
      }
      if (!_modelReady.isCompleted) _modelReady.complete();
    } catch (e) {
      debugPrint('CutInOverlay: failed to load model: $e');
      if (!_modelReady.isCompleted) _modelReady.complete();
    }
  }

  Future<void> _startSequence() async {
    debugPrint('[CutIn] _startSequence: begin');
    // Signal native window to become visible (alphaValue 0 → 1)
    _windowReadyChannel.invokeMethod('show');
    debugPrint('[CutIn] Window alpha set to 1');

    // Set emotion on the controller
    widget.controller.showExpression(widget.emotion, widget.message);

    // Phase 1: Background slides in (parallel with model load)
    debugPrint('[CutIn] Phase 1: BG slide in + model load');
    await Future.wait([
      _bgController.forward(),
      _modelReady.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => debugPrint('[CutIn] Model load timed out'),
      ),
    ]);
    if (!mounted) { debugPrint('[CutIn] unmounted after BG'); return; }

    // Flash
    _flashController.forward().then((_) {
      if (mounted) _flashController.reverse();
    });

    // Phase 2: Character slides in
    debugPrint('[CutIn] Phase 2: Char slide in');
    await _charController.forward();
    if (!mounted) { debugPrint('[CutIn] unmounted after char'); return; }

    // Phase 3: Text appears
    debugPrint('[CutIn] Phase 3: Text fade in');
    await _textController.forward();
    if (!mounted) { debugPrint('[CutIn] unmounted after text'); return; }

    // Phase 4: Hold for TTS or fixed duration
    debugPrint('[CutIn] Phase 4: Hold (TTS check)');
    bool ttsPlayed = false;
    try {
      if (await _tts.isAvailable()) {
        debugPrint('[CutIn] TTS available, synthesizing...');
        await _tts.synthesizeAndPlay(widget.message);
        ttsPlayed = true;
        debugPrint('[CutIn] TTS playback done');
      } else {
        debugPrint('[CutIn] TTS not available');
      }
    } catch (e) {
      debugPrint('[CutIn] TTS error: $e');
    }

    if (!ttsPlayed) {
      // Hold based on message length
      final holdMs = (widget.message.length * 120).clamp(2000, 5000);
      debugPrint('[CutIn] Holding for ${holdMs}ms');
      await Future<void>.delayed(Duration(milliseconds: holdMs));
    } else {
      // Brief linger after TTS
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) { debugPrint('[CutIn] unmounted after hold'); return; }

    // Phase 5: Exit
    debugPrint('[CutIn] Phase 5: Exit slide out');
    await _exitController.forward();

    debugPrint('[CutIn] Sequence complete, calling onComplete');
    widget.controller.hideExpression();
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _charController.dispose();
    _textController.dispose();
    _exitController.dispose();
    _flashController.dispose();
    _puppetController?.dispose();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Character takes roughly 65% of width, text area the rest
    final charWidth = screenSize.width * 0.65;
    final charHeight = screenSize.height;

    return Material(
      color: Colors.transparent,
      child: SlideTransition(
        position: _exitSlide,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background SVG
            SlideTransition(
              position: _bgSlide,
              child: SvgPicture.asset(
                widget.background.assetPath,
                fit: BoxFit.cover,
                width: screenSize.width,
                height: screenSize.height,
              ),
            ),

            // Character (left side)
            Positioned(
              left: 0,
              bottom: 0,
              width: charWidth,
              height: charHeight,
              child: SlideTransition(
                position: _charSlide,
                child: _buildCharacter(),
              ),
            ),

            // Dialogue text (overlaps character for wider area)
            Positioned(
              left: screenSize.width * 0.4,
              top: 0,
              right: 24,
              bottom: 0,
              child: FadeTransition(
                opacity: _textController,
                child: _buildDialogue(screenSize),
              ),
            ),

            // White flash overlay
            AnimatedBuilder(
              animation: _flashController,
              builder: (context, _) {
                return IgnorePointer(
                  child: Container(
                    color: Colors.white.withOpacity(
                      _flashController.value * 0.5,
                    ),
                  ),
                );
              },
            ),

            // Top/bottom cinematic bars
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: screenSize.height * 0.06,
              child: SlideTransition(
                position: _bgSlide,
                child: Container(color: Colors.black.withOpacity(0.7)),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: screenSize.height * 0.06,
              child: SlideTransition(
                position: _bgSlide,
                child: Container(color: Colors.black.withOpacity(0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacter() {
    if (!_modelLoaded || _puppetController == null) {
      return const SizedBox.shrink();
    }
    return PuppetWidget(
      controller: _puppetController!,
      interactive: false,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildDialogue(Size screenSize) {
    // Available width: 60% of screen minus margins
    final availableWidth = screenSize.width * 0.6 - 24;
    // Base font size, then scale down if message is long
    final baseFontSize = (screenSize.height * 0.09).clamp(40.0, 108.0);
    // Estimate CJK char width ≈ fontSize; fit message in ~1 line ideally
    final charsPerLine = (availableWidth / baseFontSize).floor();
    final fontSize = widget.message.length <= charsPerLine
        ? baseFontSize
        : (availableWidth / widget.message.length).clamp(28.0, baseFontSize);
    final strokeWidth = (fontSize * 0.06).clamp(3.0, 6.0);

    return Center(
      child: Stack(
        children: [
          // Text stroke (outline)
          Text(
            widget.message,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..color = Colors.black.withOpacity(0.8),
              decoration: TextDecoration.none,
              height: 1.3,
            ),
          ),
          // Text fill
          Text(
            widget.message,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              decoration: TextDecoration.none,
              shadows: [
                Shadow(
                  color: _accentColor.withOpacity(0.6),
                  blurRadius: 20,
                ),
              ],
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Color get _accentColor {
    return switch (widget.emotion) {
      'Joy' => const Color(0xFFFF8F00),
      'Singing' => const Color(0xFFFF8F00),
      'Blush' => const Color(0xFFE91E63),
      'Trouble' => const Color(0xFF6C3BAA),
      'Gentle' => const Color(0xFFF48FB1),
      _ => const Color(0xFFCC1133),
    };
  }

}
