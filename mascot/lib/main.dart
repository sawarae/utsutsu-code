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

  const windowSize = Size(424, 528);
  final windowOptions = WindowOptions(
    size: windowSize,
    // On macOS, window_manager handles transparency via NSWindow.
    // On Windows, transparency is handled by SetWindowCompositionAttribute
    // in C++ (flutter_window.cpp); setting these here would conflict.
    backgroundColor: Platform.isWindows ? null : Colors.transparent,
    titleBarStyle:
        Platform.isWindows ? TitleBarStyle.normal : TitleBarStyle.hidden,
    skipTaskbar: false,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (!Platform.isWindows) {
      await windowManager.setBackgroundColor(Colors.transparent);
    }

    // Position at bottom-left of screen
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final screenSize = primaryDisplay.size;
    final x = 0.0;
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

  const _AppConfig({this.modelsDir, this.model, this.signalDir});
}

/// Simple `--key value` argument parser (no external packages).
_AppConfig _parseArgs(List<String> args) {
  String? modelsDir;
  String? model;
  String? signalDir;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--models-dir':
        if (i + 1 < args.length) modelsDir = args[++i];
      case '--model':
        if (i + 1 < args.length) model = args[++i];
      case '--signal-dir':
        if (i + 1 < args.length) signalDir = args[++i];
    }
  }

  return _AppConfig(modelsDir: modelsDir, model: model, signalDir: signalDir);
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
