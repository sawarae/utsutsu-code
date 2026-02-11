import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'mascot_controller.dart';
import 'mascot_widget.dart';

void main(List<String> args) async {
  final config = _parseArgs(args);

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final windowSize = Size(config.width ?? 424, config.height ?? 528);
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

    // Position at bottom of screen (default: left edge)
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final screenSize = primaryDisplay.size;
    final x = config.offsetX ?? 0.0;
    final y = screenSize.height - windowSize.height;
    await windowManager.setPosition(Offset(x, y));

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

  const _AppConfig({
    this.modelsDir,
    this.model,
    this.signalDir,
    this.offsetX,
    this.width,
    this.height,
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
    }
  }

  return _AppConfig(
    modelsDir: modelsDir,
    model: model,
    signalDir: signalDir,
    offsetX: offsetX,
    width: width,
    height: height,
  );
}

class MascotApp extends StatefulWidget {
  final _AppConfig config;

  const MascotApp({super.key, required this.config});

  @override
  State<MascotApp> createState() => _MascotAppState();
}

class _MascotAppState extends State<MascotApp> {
  late final MascotController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MascotController(
      signalDir: widget.config.signalDir,
      modelsDir: widget.config.modelsDir,
      model: widget.config.model,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: MascotWidget(controller: _controller),
    );
  }
}
