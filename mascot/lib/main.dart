import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'mascot_controller.dart';
import 'mascot_widget.dart';
import 'wander_controller.dart';

void main(List<String> args) async {
  final config = _parseArgs(args);

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Wander mode uses a smaller window (half size)
  final defaultWidth = config.wander ? 132.0 : 424.0;
  final defaultHeight = config.wander ? 264.0 : 528.0;
  final windowSize =
      Size(config.width ?? defaultWidth, config.height ?? defaultHeight);
  final windowOptions = WindowOptions(
    size: windowSize,
    // On macOS, window_manager handles transparency via NSWindow.
    // On Windows, DwmExtendFrameIntoClientArea in C++ (flutter_window.cpp)
    // creates the glass region; Flutter must also set transparent background
    // so that alpha=0 pixels pass through to the DWM compositor.
    backgroundColor: Colors.transparent,
    titleBarStyle:
        Platform.isWindows ? TitleBarStyle.normal : TitleBarStyle.hidden,
    skipTaskbar: false,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setBackgroundColor(Colors.transparent);

    if (!config.wander) {
      // Position at bottom of screen (default: left edge)
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenSize = primaryDisplay.size;
      final x = config.offsetX ?? 0.0;
      final y = screenSize.height - windowSize.height;
      await windowManager.setPosition(Offset(x, y));
    }
    // Wander mode: WanderController handles positioning

    await windowManager.show();
  });

  runApp(MascotApp(config: config));
}

/// Parsed CLI arguments.
class _AppConfig {
  final String? modelsDir;
  final String? model;
  final String? signalDir;
  final double? offsetX;
  final double? width;
  final double? height;
  final bool wander;

  const _AppConfig({
    this.modelsDir,
    this.model,
    this.signalDir,
    this.offsetX,
    this.width,
    this.height,
    this.wander = false,
  });
}

/// Simple `--key value` argument parser (no external packages).
_AppConfig _parseArgs(List<String> args) {
  String? modelsDir;
  String? model;
  String? signalDir;
  double? offsetX;
  double? width;
  double? height;
  bool wander = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--models-dir':
        if (i + 1 < args.length) modelsDir = args[++i];
      case '--model':
        if (i + 1 < args.length) model = args[++i];
      case '--signal-dir':
        if (i + 1 < args.length) signalDir = args[++i];
      case '--offset-x':
        if (i + 1 < args.length) offsetX = double.tryParse(args[++i]);
      case '--width':
        if (i + 1 < args.length) width = double.tryParse(args[++i]);
      case '--height':
        if (i + 1 < args.length) height = double.tryParse(args[++i]);
      case '--wander':
        wander = true;
    }
  }

  return _AppConfig(
    modelsDir: modelsDir,
    model: model,
    signalDir: signalDir,
    offsetX: offsetX,
    width: width,
    height: height,
    wander: wander,
  );
}

/// A child mascot spawned via signal file.
class _ChildMascot {
  final String signalDir;
  final MascotController controller;

  _ChildMascot({required this.signalDir, required this.controller});
}

class MascotApp extends StatefulWidget {
  final _AppConfig config;

  const MascotApp({super.key, required this.config});

  @override
  State<MascotApp> createState() => _MascotAppState();
}

class _MascotAppState extends State<MascotApp> {
  static const _mainWidth = 424.0;
  static const _childWidth = 264.0;
  static const _windowHeight = 528.0;

  late final MascotController _controller;
  WanderController? _wanderController;
  final List<_ChildMascot> _children = [];
  Timer? _spawnTimer;
  late final String _spawnSignalPath;

  @override
  void initState() {
    super.initState();
    _controller = MascotController(
      signalDir: widget.config.signalDir,
      modelsDir: widget.config.modelsDir,
      model: widget.config.model,
    );

    if (widget.config.wander) {
      final windowW = widget.config.width ?? 132.0;
      final windowH = widget.config.height ?? 264.0;
      _wanderController = WanderController(
        windowWidth: windowW,
        windowHeight: windowH,
      );
      _wanderController!.start();
    }

    // Resolve spawn signal path from the main signal directory
    final signalDir = widget.config.signalDir ?? _defaultSignalDir();
    _spawnSignalPath = '$signalDir/spawn_child';

    // Poll for child spawn signals (only in non-wander mode)
    if (!widget.config.wander) {
      _spawnTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _checkSpawnSignal(),
      );
    }
  }

  static String _defaultSignalDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return '$home/.claude/utsutsu-code';
  }

  void _checkSpawnSignal() {
    final file = File(_spawnSignalPath);
    if (!file.existsSync()) return;

    debugPrint('[Spawn] Signal file found: $_spawnSignalPath');
    try {
      final content = file.readAsStringSync().trim();
      file.deleteSync();
      debugPrint('[Spawn] Content: $content');

      final json = jsonDecode(content) as Map<String, dynamic>;
      final signalDir = json['signal_dir'] as String;
      final model = json['model'] as String? ?? 'blend_shape_mini';
      debugPrint('[Spawn] signalDir=$signalDir model=$model');

      // Clean any stale dismiss file
      final dismissFile = File('$signalDir/mascot_dismiss');
      if (dismissFile.existsSync()) {
        dismissFile.deleteSync();
        debugPrint('[Spawn] Cleaned stale dismiss file');
      }

      // Ensure signal dir exists
      Directory(signalDir).createSync(recursive: true);

      debugPrint('[Spawn] Creating MascotController...');
      final controller = MascotController(
        signalDir: signalDir,
        modelsDir: widget.config.modelsDir,
        model: model,
      );
      debugPrint('[Spawn] MascotController created, model=${controller.modelConfig}');

      setState(() {
        _children.add(_ChildMascot(
          signalDir: signalDir,
          controller: controller,
        ));
        debugPrint('[Spawn] Added child, total children=${_children.length}');
      });
      _updateWindowSize();
    } catch (e, st) {
      debugPrint('Failed to spawn child mascot: $e\n$st');
    }
  }

  void _removeChildBySignalDir(String signalDir) {
    final index = _children.indexWhere((c) => c.signalDir == signalDir);
    if (index == -1) return;
    _children[index].controller.dispose();
    setState(() {
      _children.removeAt(index);
    });
    _updateWindowSize();
  }

  Future<void> _updateWindowSize() async {
    final width = _mainWidth + _childWidth * _children.length;
    debugPrint('[Spawn] Resizing window to ${width}x$_windowHeight (children=${_children.length})');
    await windowManager.setSize(Size(width, _windowHeight));
    final actual = await windowManager.getSize();
    debugPrint('[Spawn] Window size after resize: $actual');
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    for (final child in _children) {
      child.controller.dispose();
    }
    _wanderController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.wander) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.transparent,
          canvasColor: Colors.transparent,
        ),
        home: MascotWidget(
          controller: _controller,
          wanderController: _wanderController,
        ),
      );
    }

    debugPrint('[Build] children=${_children.length}');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: _mainWidth,
            height: _windowHeight,
            child: MascotWidget(controller: _controller),
          ),
          for (var i = 0; i < _children.length; i++)
            SizedBox(
              width: _childWidth,
              height: _windowHeight,
              child: MascotWidget(
                key: ValueKey(_children[i].signalDir),
                controller: _children[i].controller,
                onDismissComplete: () => _removeChildBySignalDir(_children[i].signalDir),
              ),
            ),
        ],
      ),
    );
  }
}
