import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:utsutsu2d/utsutsu2d.dart';
import 'package:window_manager/window_manager.dart';

import 'mascot_controller.dart';

class MascotWidget extends StatefulWidget {
  final MascotController controller;

  const MascotWidget({super.key, required this.controller});

  @override
  State<MascotWidget> createState() => _MascotWidgetState();
}

class _MascotWidgetState extends State<MascotWidget>
    with SingleTickerProviderStateMixin {
  MascotController get _controller => widget.controller;
  late final AnimationController _fadeController;
  bool _showBubble = false;
  String _bubbleText = '';

  PuppetController? _puppetController;
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _controller.addListener(_onControllerChanged);
    _loadModel();
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
      final fileName = config.modelFilePath.split('/').last;
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

  void _onControllerChanged() {
    if (_modelLoaded) {
      _syncParameters();
    }

    if (_controller.isSpeaking && _controller.message.isNotEmpty) {
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
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _fadeController.dispose();
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
                  child: SizedBox(
                    width: 264,
                    height: 528,
                    child: _buildCharacter(),
                  ),
                ),
                if (_showBubble)
                  Positioned(
                    left: 170,
                    top: 40,
                    right: 0,
                    child: FadeTransition(
                      opacity: _fadeController,
                      child: _SpeechBubble(text: _bubbleText),
                    ),
                  ),
                if (io.Platform.isWindows)
                  Positioned(
                    top: 0,
                    left: 228,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => windowManager.close(),
                        child: Container(
                          width: 36,
                          height: 36,
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
            child: Text(
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
