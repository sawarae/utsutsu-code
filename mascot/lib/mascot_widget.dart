import 'dart:async' show Timer;
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
import 'wander_controller.dart';

class MascotWidget extends StatefulWidget {
  final MascotController controller;
  final WanderController? wanderController;
  final bool outlineEnabled;

  /// Override render dimensions for swarm LOD0 mode.
  /// When set, camera zoom is scaled by renderWidth / 264.0
  /// and the character area uses these dimensions instead of defaults.
  final double? renderWidth;
  final double? renderHeight;

  /// Called when the dismiss animation completes.
  /// If null, the window is closed (main mascot behavior).
  final VoidCallback? onDismissComplete;

  const MascotWidget({
    super.key,
    required this.controller,
    this.wanderController,
    this.outlineEnabled = false,
    this.renderWidth,
    this.renderHeight,
    this.onDismissComplete,
  });

  @override
  State<MascotWidget> createState() => _MascotWidgetState();
}

class _MascotWidgetState extends State<MascotWidget>
    with TickerProviderStateMixin {
  static const _clickThroughChannel = MethodChannel('mascot/click_through');
  static const _nativeDragChannel = MethodChannel('mascot/native_drag');
  static const _windowReadyChannel = MethodChannel('mascot/window_ready');
  static const _wanderModeChannel = MethodChannel('mascot/wander_mode');
  static const _windowDragChannel = MethodChannel('mascot/window_drag');

  // Close button position/size in logical coordinates.
  // Must match kCloseBtn* constants in flutter_window.h.
  static const _closeBtnLeft = 228.0;
  static const _closeBtnTop = 0.0;
  static const _closeBtnSize = 36.0;

  MascotController get _controller => widget.controller;
  WanderController? get _wander => widget.wanderController;
  bool get _isWander => _wander != null;
  late final AnimationController _fadeController;
  late final AnimationController _modelFadeController;
  late final AnimationController _jumpController;
  late final Animation<double> _jumpAnimation;
  late final AnimationController _dismissController;
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
    _modelFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _jumpAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -20), weight: 30),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -20,
          end: 0,
        ).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 70,
      ),
    ]).animate(_jumpController);
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expressionService = ExpressionService(_controller);
    _expressionService.addListener(_onBubblesChanged);
    _controller.addListener(_onControllerChanged);
    _wander?.addListener(_onWanderChanged);
    _wander?.onCollision = () {
      _expressionService.expressCollision();
    };
    _loadModel();
    // In wander mode, disable native window dragging so Flutter handles it,
    // and skip CGWindowListCreateImage-based click-through tracking
    if (_isWander && io.Platform.isMacOS) {
      _nativeDragChannel.invokeMethod('setEnabled', false);
      _wanderModeChannel.invokeMethod('setEnabled', true);
    }
    // On Windows wander mode, listen for native drag events (HTCAPTION drag)
    // to sync WanderController position and apply inertia on release.
    if (_isWander && io.Platform.isWindows) {
      _windowDragChannel.setMethodCallHandler(_handleWindowDrag);
    }
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
        var zoom = config.cameraZoom;
        // Scale zoom for wander mode's smaller window or swarm LOD0
        if (widget.renderWidth != null) {
          zoom *= widget.renderWidth! / 264.0;
        } else if (_isWander) {
          zoom *= _wander!.windowWidth / 264.0;
        }
        camera.zoom = zoom;
        camera.position = Vec2(0, config.cameraY);
      }

      if (mounted) {
        setState(() {
          _puppetController = pc;
          _modelLoaded = true;
        });
        _syncParameters();
        _modelFadeController.forward();
        // Signal native window to become visible (prevents yellow flash)
        if (io.Platform.isMacOS) {
          _windowReadyChannel.invokeMethod('show');
        }
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

    final charW = _isWander ? _wander!.windowWidth : 264.0;
    final charH = _isWander ? _wander!.windowHeight : 528.0;
    final regions = <Map<String, double>>[
      {'x': 0.0, 'y': 0.0, 'w': charW, 'h': charH},
    ];

    if (_showBubble) {
      // Measure actual bubble size if available, otherwise use generous estimate
      final bubbleBox =
          _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
      final bubbleH = bubbleBox?.size.height ?? 120.0;
      // Bubble: Positioned(left: 170, top: 40, right: 0) → x=150 to include tail
      regions.add({'x': 150.0, 'y': 40.0, 'w': 274.0, 'h': bubbleH + 20});
    }

    // Expression bubbles from right-click
    for (var i = 0; i < _expressionService.activeBubbles.length; i++) {
      final top = 40.0 + i * 50.0;
      regions.add({'x': 150.0, 'y': top, 'w': 274.0, 'h': 60.0});
    }

    _clickThroughChannel.invokeMethod('setOpaqueRegions', regions);
  }

  void _onControllerChanged() {
    // Handle dismiss signal: play "pop" animation then close/notify
    if (_controller.isDismissed && !_dismissController.isAnimating) {
      _dismissController.forward().then((_) {
        if (widget.onDismissComplete != null) {
          widget.onDismissComplete!();
        } else {
          windowManager.close();
          // Fallback: force exit if windowManager.close() doesn't terminate
          Future.delayed(const Duration(seconds: 1), () => io.exit(0));
        }
      });
      return;
    }

    if (_modelLoaded) {
      _syncParameters();
    }

    final bubbleChanged = _showBubble != _controller.isSpeaking;

    final hasMessage =
        _controller.isSpeaking &&
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

  Map<String, double>? _lastWanderOverrides;

  // Position samples for native drag velocity (Dart coordinates)
  final List<(int, double, double)> _nativeDragSamples = [];
  Timer? _nativeDragPollTimer;

  Future<dynamic> _handleWindowDrag(MethodCall call) async {
    final wander = _wander;
    if (wander == null) return;
    if (call.method == 'dragStart') {
      wander.startDrag();
      // Poll window position during drag for velocity in Dart coordinates
      _nativeDragSamples.clear();
      _nativeDragPollTimer?.cancel();
      _nativeDragPollTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) async {
          final pos = await windowManager.getPosition();
          final now = DateTime.now().millisecondsSinceEpoch;
          _nativeDragSamples.add((now, pos.dx, pos.dy));
          if (_nativeDragSamples.length > 5) _nativeDragSamples.removeAt(0);
        },
      );
    } else if (call.method == 'dragEnd') {
      _nativeDragPollTimer?.cancel();
      final pos = await windowManager.getPosition();
      // Compute velocity from Dart-side position samples
      double velX = 0, velY = 0;
      if (_nativeDragSamples.length >= 2) {
        final first = _nativeDragSamples.first;
        final last = _nativeDragSamples.last;
        final dtMs = last.$1 - first.$1;
        if (dtMs > 0) {
          velX = (last.$2 - first.$2) / dtMs * 1000; // px/sec
          velY = (last.$3 - first.$3) / dtMs * 1000;
        }
      }
      _nativeDragSamples.clear();
      wander.endNativeDrag(pos.dx, pos.dy, velX, velY);
    }
  }

  void _onWanderChanged() {
    if (!mounted) return;
    // Only sync parameter overrides when sparkles/arm actually changed
    final overrides = _wander!.parameterOverrides;
    if (!_mapEquals(overrides, _lastWanderOverrides)) {
      _lastWanderOverrides = overrides;
      _controller.setWanderOverrides(overrides);
    }
    // Rebuild for bounce/squish transform (lightweight setState only)
    setState(() {});
  }

  static bool _mapEquals(Map<String, double> a, Map<String, double>? b) {
    if (b == null || a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _onBubblesChanged() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pushOpaqueRegions();
      });
    }
  }

  @override
  void dispose() {
    _nativeDragPollTimer?.cancel();
    _wander?.removeListener(_onWanderChanged);
    _controller.removeListener(_onControllerChanged);
    _expressionService.removeListener(_onBubblesChanged);
    _expressionService.dispose();
    _fadeController.dispose();
    _modelFadeController.dispose();
    _jumpController.dispose();
    _dismissController.dispose();
    _puppetController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_modelLoaded) {
      return const ColoredBox(
        color: Colors.transparent,
        child: SizedBox.expand(),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _dismissController,
        builder: (context, child) {
          final t = _dismissController.value;
          // "Pop" effect: slight scale-up then shrink to 0, with fade
          final scale = t < 0.2 ? 1.0 + t * 0.5 : (1.0 - t) * 1.25;
          return Transform.scale(
            scale: scale.clamp(0.0, 1.1),
            alignment: Alignment.bottomCenter,
            child: Opacity(opacity: (1.0 - t).clamp(0.0, 1.0), child: child),
          );
        },
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final charW = widget.renderWidth ??
                (_isWander ? _wander!.windowWidth : 264.0);
            // Wander mode / swarm LOD0: fill the entire area so the
            // character head sits near the top and the speech bubble
            // (overlaid at top:0) appears right above it.
            final charH = widget.renderHeight ??
                (_isWander ? _wander!.windowHeight.toDouble() : 528.0);

            // Position bubble above the character head in wander mode.
            // macOS: character fills the window well → 20% from top.
            // Windows: smaller zoom leaves more headroom → 8% from top.
            final wanderBubbleTop = _isWander
                ? (charH * (io.Platform.isWindows ? 0.08 : 0.20)).roundToDouble()
                : 0.0;

            return FadeTransition(
              opacity: _modelFadeController,
              child: Stack(
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
                        width: charW,
                        height: charH,
                        child: GestureDetector(
                          // Opaque hit testing so drags work on transparent areas
                          behavior: _isWander
                              ? HitTestBehavior.opaque
                              : HitTestBehavior.deferToChild,
                          onSecondaryTap: () {
                            _jumpController.forward(from: 0);
                            _expressionService.expressRandom();
                          },
                          onPanStart: _isWander
                              ? (_) => _wander!.startDrag()
                              : null,
                          onPanUpdate: _isWander
                              ? (details) => _wander!.updateDrag(details.delta)
                              : null,
                          onPanEnd: _isWander
                              ? (details) => _wander!.endDrag()
                              : null,
                          child: _buildWanderWrapper(
                            child: _isWander
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: _buildCharacter(),
                                  )
                                : _buildCharacter(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_showBubble)
                    _isWander
                        ? Positioned(
                            left: 4,
                            top: wanderBubbleTop,
                            right: 4,
                            child: FadeTransition(
                              key: _bubbleKey,
                              opacity: _fadeController,
                              child: _WanderBubble(text: _bubbleText),
                            ),
                          )
                        : Positioned(
                            left: 170,
                            top: 40,
                            right: 0,
                            child: FadeTransition(
                              key: _bubbleKey,
                              opacity: _fadeController,
                              child: _SpeechBubble(text: _bubbleText),
                            ),
                          ),
                  // Expression bubbles from right-click
                  for (
                    var i = 0;
                    i < _expressionService.activeBubbles.length;
                    i++
                  )
                    _isWander
                        ? Positioned(
                            left: 4,
                            top: (wanderBubbleTop - (i + 1) * 30.0).clamp(
                              0.0,
                              wanderBubbleTop,
                            ),
                            right: 4,
                            child: _WanderBubble(
                              text: _expressionService.activeBubbles[i].text,
                            ),
                          )
                        : Positioned(
                            left: 170,
                            top: 40.0 + i * 50.0,
                            right: 0,
                            child: _SpeechBubble(
                              text: _expressionService.activeBubbles[i].text,
                              showTail: i == 0,
                            ),
                          ),
                  if (!_isWander)
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
              ),
            );
          },
        ),
      ),
    );
  }

  /// Wraps the character with wander-mode transforms: horizontal flip,
  /// bounce offset, and squishy deformation.
  Widget _buildWanderWrapper({required Widget child}) {
    if (!_isWander) return child;
    final wander = _wander!;
    final (sx, sy) = wander.squishScale;

    // Layer 1: Squish (mochi deformation) anchored at bottom-center
    Widget result = Transform.scale(
      scaleX: sx,
      scaleY: sy,
      alignment: Alignment.bottomCenter,
      child: child,
    );

    // Layer 2: Bounce offset (negative = up)
    result = Transform.translate(
      offset: Offset(0, wander.bounceOffset),
      child: result,
    );

    // Layer 3: Horizontal flip when facing right (model default faces left)
    if (!wander.facingLeft) {
      result = Transform.flip(flipX: true, child: result);
    }

    return result;
  }

  Widget _buildCharacter() {
    Widget character;

    if (_modelLoaded && _puppetController != null) {
      character = PuppetWidget(
        controller: _puppetController!,
        interactive: false,
        backgroundColor: Colors.transparent,
      );
    } else if (!_modelLoaded) {
      // Hide until model is loaded to prevent initial flicker
      return const SizedBox.shrink();
    } else {
      // Fallback to static PNG images loaded from filesystem
      final config = _controller.modelConfig;
      final path = _controller.showOpenMouth
          ? config.fallbackMouthOpen
          : config.fallbackMouthClosed;
      final file = io.File(path);
      if (file.existsSync()) {
        character = Image.file(file, fit: BoxFit.contain);
      } else {
        character = const Center(
          child: Icon(Icons.person, size: 128, color: Colors.grey),
        );
      }
    }

    if (widget.outlineEnabled) {
      character = _buildOutline(character);
    }
    return character;
  }

  /// Wraps the character with a white border and black outline using
  /// dilate image filters to expand the character's silhouette.
  Widget _buildOutline(Widget child) {
    return Stack(
      children: [
        // Layer 1: Black outline (outermost, largest dilation)
        ImageFiltered(
          imageFilter: ui.ImageFilter.dilate(radiusX: 6, radiusY: 6),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.black,
              ui.BlendMode.srcATop,
            ),
            child: child,
          ),
        ),
        // Layer 2: White border (smaller dilation)
        ImageFiltered(
          imageFilter: ui.ImageFilter.dilate(radiusX: 4, radiusY: 4),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.white,
              ui.BlendMode.srcATop,
            ),
            child: child,
          ),
        ),
        // Layer 3: Original character on top
        child,
      ],
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String text;
  final bool showTail;

  const _SpeechBubble({required this.text, this.showTail = true});

  bool get _isLoading => text == ExpressionService.loadingMarker;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTail)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CustomPaint(
              size: const Size(20, 14),
              painter: _BubbleTailPainter(),
            ),
          )
        else
          const SizedBox(width: 20),
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
        return CustomPaint(painter: _SquigglyPainter(_controller.value));
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
      final y =
          midY +
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

/// Compact speech bubble for wander mode, displayed above the character
/// with a downward-pointing tail.
class _WanderBubble extends StatelessWidget {
  final String text;

  const _WanderBubble({required this.text});

  bool get _isLoading => text == ExpressionService.loadingMarker;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: _isLoading
              ? const SizedBox(width: 40, height: 10, child: _SquigglyLoader())
              : Text(
                  text,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.black87,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        CustomPaint(size: const Size(10, 6), painter: _DownTailPainter()),
      ],
    );
  }
}

class _DownTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
