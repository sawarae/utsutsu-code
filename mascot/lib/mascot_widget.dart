import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:utsutsu2d/utsutsu2d.dart' hide Animation;
import 'package:window_manager/window_manager.dart';

import 'expression_service.dart';
import 'mascot_controller.dart';

class MascotWidget extends StatefulWidget {
  final MascotController controller;

  const MascotWidget({super.key, required this.controller});

  @override
  State<MascotWidget> createState() => _MascotWidgetState();
}

class _MascotWidgetState extends State<MascotWidget>
    with TickerProviderStateMixin {
  static const _clickThroughChannel = MethodChannel('mascot/click_through');

  // Close button position/size in logical coordinates.
  // Must match kCloseBtn* constants in flutter_window.h.
  static const _closeBtnLeft = 228.0;
  static const _closeBtnTop = 0.0;
  static const _closeBtnSize = 36.0;

  MascotController get _controller => widget.controller;
  late final AnimationController _fadeController;
  late final AnimationController _jumpController;
  late final Animation<double> _jumpAnimation;
  late final ExpressionService _expressionService;
  bool _showBubble = false;
  String _bubbleText = '';

  PuppetController? _puppetController;
  bool _modelLoaded = false;

  /// Key for the speech bubble to measure its actual size.
  final _bubbleKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _jumpAnimation = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: -20), weight: 30),
      TweenSequenceItem(
          tween: Tween<double>(begin: -20, end: 0)
              .chain(CurveTween(curve: Curves.bounceOut)),
          weight: 70),
    ]).animate(_jumpController);
    _expressionService = ExpressionService(_controller);
    _controller.addListener(_onControllerChanged);
    _loadModel();
    // Push initial opaque regions after first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushOpaqueRegions();
    });
  }

  Future<void> _loadModel() async {
    try {
      final config = _controller.modelConfig;
      // Load .inp from filesystem
      final file = io.File(config.modelFilePath);
      if (!file.existsSync()) {
        debugPrint('Model file not found: ${config.modelFilePath}');
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

      // Create and configure PuppetController
      final pc = PuppetController();
      await pc.loadModel(model, textures);

      // Set camera from model config
      final camera = pc.camera;
      if (camera != null) {
        camera.zoom = config.cameraZoom;
        camera.position = Vec2(0, config.cameraY);
      }

      if (mounted) {
        setState(() {
          _puppetController = pc;
          _modelLoaded = true;
        });
        _syncParameters();
      }
    } catch (e) {
      debugPrint('Failed to load utsutsu2d model: $e');
    }
  }

  void _syncParameters() {
    final pc = _puppetController;
    if (pc == null || pc.puppet == null) return;

    final puppet = pc.puppet!;
    final params = _controller.parameters;
    for (final entry in params.entries) {
      puppet.setParam(entry.key, entry.value);
    }
    pc.updateManual();
  }

  /// Push opaque regions to the native side for click-through hit testing.
  /// Called on init and whenever the bubble state changes.
  void _pushOpaqueRegions() {
    if (!io.Platform.isWindows) return;

    final regions = <Map<String, double>>[
      // Character: 264x528 at bottom-left (full window height)
      {'x': 0.0, 'y': 0.0, 'w': 264.0, 'h': 528.0},
    ];

    if (_showBubble) {
      // Measure actual bubble size if available, otherwise use generous estimate
      final bubbleBox =
          _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
      final bubbleH = bubbleBox?.size.height ?? 120.0;
      // Bubble: Positioned(left: 170, top: 40, right: 0) → x=150 to include tail
      regions.add({'x': 150.0, 'y': 40.0, 'w': 274.0, 'h': bubbleH + 20});
    }

    _clickThroughChannel.invokeMethod('setOpaqueRegions', regions);
  }

  void _onControllerChanged() {
    if (_modelLoaded) {
      _syncParameters();
    }

    final bubbleChanged = _showBubble != _controller.isSpeaking;

    final hasMessage = _controller.isSpeaking &&
        (_controller.message.isNotEmpty ||
            _controller.message == ExpressionService.loadingMarker);
    if (hasMessage) {
      if (!_showBubble || _bubbleText != _controller.message) {
        setState(() {
          _showBubble = true;
          _bubbleText = _controller.message;
        });
        _fadeController.value = 1.0;
      }
    } else if (!_controller.isSpeaking && _showBubble) {
      _fadeController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _showBubble = false;
            _bubbleText = '';
          });
          _pushOpaqueRegions();
        }
      });
    }

    if (bubbleChanged && _showBubble) {
      // Push after frame so bubble size is measured
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pushOpaqueRegions();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _expressionService.dispose();
    _fadeController.dispose();
    _jumpController.dispose();
    _puppetController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _jumpAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _jumpAnimation.value),
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: 264,
                      height: 528,
                      child: GestureDetector(
                        onSecondaryTap: () {
                          _jumpController.forward(from: 0);
                          _expressionService.expressRandom();
                        },
                        child: _buildCharacter(),
                      ),
                    ),
                  ),
                ),
                if (_showBubble)
                  Positioned(
                    left: 170,
                    top: 40,
                    right: 0,
                    child: FadeTransition(
                      key: _bubbleKey,
                      opacity: _fadeController,
                      child: _SpeechBubble(text: _bubbleText),
                    ),
                  ),
                if (io.Platform.isWindows)
                  Positioned(
                    top: _closeBtnTop,
                    left: _closeBtnLeft,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => windowManager.close(),
                        child: Container(
                          width: _closeBtnSize,
                          height: _closeBtnSize,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
  }

  Widget _buildCharacter() {
    if (_modelLoaded && _puppetController != null) {
      return PuppetWidget(
        controller: _puppetController!,
        interactive: false,
        backgroundColor: Colors.transparent,
      );
    }

    // Fallback to static PNG images loaded from filesystem
    final config = _controller.modelConfig;
    final path = _controller.showOpenMouth
        ? config.fallbackMouthOpen
        : config.fallbackMouthClosed;
    final file = io.File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.contain);
    }

    // Final fallback: grey placeholder icon
    return const Center(
      child: Icon(Icons.person, size: 128, color: Colors.grey),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String text;

  const _SpeechBubble({required this.text});

  bool get _isLoading => text == ExpressionService.loadingMarker;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CustomPaint(
            size: const Size(20, 14),
            painter: _BubbleTailPainter(),
          ),
        ),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(1, 2),
                ),
              ],
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 60,
                    height: 16,
                    child: _SquigglyLoader(),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                      decoration: TextDecoration.none,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Animated squiggly line loader shown while Haiku generates a phrase.
class _SquigglyLoader extends StatefulWidget {
  const _SquigglyLoader();

  @override
  State<_SquigglyLoader> createState() => _SquigglyLoaderState();
}

class _SquigglyLoaderState extends State<_SquigglyLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _SquigglyPainter(_controller.value),
        );
      },
    );
  }
}

class _SquigglyPainter extends CustomPainter {
  final double phase;

  _SquigglyPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final midY = size.height / 2;
    final amplitude = 4.0;
    final wavelength = size.width / 3;
    final phaseOffset = phase * 2 * math.pi;

    path.moveTo(0, midY);
    for (double x = 0; x <= size.width; x += 1) {
      final y = midY +
          amplitude * math.sin((x / wavelength) * 2 * math.pi + phaseOffset);
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SquigglyPainter old) => old.phase != phase;
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height * 0.6)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
