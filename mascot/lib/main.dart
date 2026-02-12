import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform, Process, ProcessStartMode;

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

  // Wander mode uses a smaller window; extra width for outline dilation padding
  final defaultWidth = config.wander ? 190.0 : 424.0;
  final defaultHeight = config.wander ? 350.0 : 528.0;
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
    // Hide traffic light buttons in wander mode. Must be set here (not in
    // Swift awakeFromNib) because window_manager's setTitleBarStyle
    // force-unwraps standardWindowButton(.closeButton) superview.
    windowButtonVisibility: !config.wander,
    skipTaskbar: false,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setBackgroundColor(Colors.transparent);

    // Hide traffic light buttons in wander mode (macOS)
    // Disable window-level dragging so Flutter GestureDetector handles it
    if (config.wander && Platform.isMacOS) {
      await windowManager.setClosable(false);
      await windowManager.setMinimizable(false);
      await windowManager.setMovable(false);
    }

    if (config.wander) {
      // Place off-screen before show() so the window isn't visible until
      // WanderController.start() begins the drop animation.
      await windowManager.setPosition(Offset(0, -windowSize.height * 2));
    } else {
      // Position at bottom of screen (default: left edge)
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenSize = primaryDisplay.size;
      final x = config.offsetX ?? 0.0;
      final y = screenSize.height - windowSize.height;
      await windowManager.setPosition(Offset(x, y));
    }

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
  final bool outline;

  const _AppConfig({
    this.modelsDir,
    this.model,
    this.signalDir,
    this.offsetX,
    this.width,
    this.height,
    this.wander = false,
    this.outline = true,
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
  bool outline = true;

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
      case '--no-wander':
        wander = false;
      case '--outline':
        outline = true;
      case '--no-outline':
        outline = false;
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
    outline: outline,
  );
}

/// A child mascot spawned via signal file.
class _ChildMascot {
  final String signalDir;
  final MascotController controller;

  _ChildMascot({required this.signalDir, required this.controller});
}

/// A wander-mode child process spawned by the parent.
class _WanderChild {
  final int pid;
  final String signalDir;
  _WanderChild({required this.pid, required this.signalDir});
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
  static const _maxChildren = 5;

  late final MascotController _controller;
  WanderController? _wanderController;
  final List<_ChildMascot> _children = [];
  final List<_WanderChild> _wanderChildren = [];
  Timer? _spawnTimer;
  late final String _spawnSignalPath;
  final List<Timer> _ttsTimers = [];

  @override
  void initState() {
    super.initState();
    _controller = MascotController(
      signalDir: widget.config.signalDir,
      modelsDir: widget.config.modelsDir,
      model: widget.config.model,
    );

    if (widget.config.wander) {
      final windowW = widget.config.width ?? 150.0;
      final windowH = widget.config.height ?? 350.0;
      _wanderController = WanderController(
        windowWidth: windowW,
        windowHeight: windowH,
        signalDir: widget.config.signalDir,
      );
      _wanderController!.start();
    }

    // Resolve spawn signal path from the main signal directory
    final signalDir = widget.config.signalDir ?? _defaultSignalDir();
    _spawnSignalPath = '$signalDir/spawn_child';

    // Clean up zombie wander children from a previous (crashed) parent
    if (!widget.config.wander) {
      _cleanStaleChildren();
    }

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

  /// Kill zombie wander children left behind by a previous parent that
  /// crashed before its [dispose] could run, and clean up orphaned task dirs.
  void _cleanStaleChildren() {
    final signalDir = widget.config.signalDir ?? _defaultSignalDir();

    // 1. Kill zombie wander children from wander_children.json
    final childrenFile = File('$signalDir/wander_children.json');
    final knownSignalDirs = <String>{};
    if (childrenFile.existsSync()) {
      try {
        final data =
            jsonDecode(childrenFile.readAsStringSync()) as List<dynamic>;
        for (final entry in data) {
          final pid = entry['pid'] as int?;
          final dir = entry['signalDir'] as String?;
          if (pid != null) {
            try {
              Process.killPid(pid);
            } catch (_) {}
          }
          if (dir != null) {
            knownSignalDirs.add(dir);
            try {
              File('$dir/mascot_dismiss').writeAsStringSync('');
            } catch (_) {}
          }
        }
        childrenFile.deleteSync();
      } catch (e) {
        debugPrint('Failed to clean stale children: $e');
        try {
          childrenFile.deleteSync();
        } catch (_) {}
      }
    }

    // 2. Clean orphaned task-* directories
    try {
      final parentDir = Directory(signalDir);
      if (parentDir.existsSync()) {
        for (final entity in parentDir.listSync()) {
          if (entity is Directory) {
            final name = entity.path.split('/').last;
            if (!name.startsWith('task-')) continue;

            final hasDismiss =
                File('${entity.path}/mascot_dismiss').existsSync();
            final isTracked = knownSignalDirs.contains(entity.path);

            // Delete if dismissed or not tracked by any active wander child
            if (hasDismiss || !isTracked) {
              try {
                entity.deleteSync(recursive: true);
                debugPrint('Cleaned stale task dir: ${entity.path}');
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to clean orphaned task dirs: $e');
    }

    // 3. Remove legacy _active_task_mascots tracking file
    try {
      final legacyFile = File('$signalDir/_active_task_mascots');
      if (legacyFile.existsSync()) {
        legacyFile.deleteSync();
        debugPrint('Removed legacy _active_task_mascots file');
      }
    } catch (_) {}
  }

  /// Persist current wander child PIDs to disk so they can be cleaned up
  /// if the parent crashes.
  void _persistChildPids() {
    final signalDir = widget.config.signalDir ?? _defaultSignalDir();
    final childrenFile = File('$signalDir/wander_children.json');
    try {
      final data = _wanderChildren
          .map((c) => {'pid': c.pid, 'signalDir': c.signalDir})
          .toList();
      childrenFile.writeAsStringSync(jsonEncode(data));
    } catch (_) {}
  }

  void _checkSpawnSignal() {
    final file = File(_spawnSignalPath);
    if (!file.existsSync()) return;

    // Atomically claim the signal file to prevent race conditions
    final claimedPath = '${_spawnSignalPath}_processing';
    try {
      file.renameSync(claimedPath);
    } catch (_) {
      return; // Another poller already claimed it
    }

    try {
      final claimedFile = File(claimedPath);
      final content = claimedFile.readAsStringSync().trim();
      claimedFile.deleteSync();

      final json = jsonDecode(content) as Map<String, dynamic>;

      // New format: only task_id; parent decides policy
      final taskId = json['task_id'] as String;
      final parentDir = widget.config.signalDir ?? _defaultSignalDir();
      final signalDir = '$parentDir/task-$taskId';

      // Parent creates dir (moved from hook)
      Directory(signalDir).createSync(recursive: true);

      // Parent cleans stale dismiss (moved from hook)
      final dismissFile = File('$signalDir/mascot_dismiss');
      if (dismissFile.existsSync()) dismissFile.deleteSync();

      // Parent decides model and wander policy
      _spawnWanderProcess(signalDir, 'blend_shape_mini');

      // Parent sends delayed TTS (moved from hook's sleep 2 && TTS)
      _sendDelayedTts(signalDir);
    } catch (e) {
      debugPrint('Failed to spawn child mascot: $e');
    }
  }

  /// Send initial TTS to a newly spawned child mascot after a short delay,
  /// giving it time to initialize.
  void _sendDelayedTts(String signalDir) {
    final writeTimer = Timer(const Duration(seconds: 2), () {
      final speakingFile = File('$signalDir/mascot_speaking');
      try {
        speakingFile.writeAsStringSync(
          jsonEncode({'message': 'タスク開始します', 'emotion': 'Gentle'}),
        );
      } catch (_) {
        return; // signal dir may have been cleaned up already
      }
      final clearTimer = Timer(const Duration(seconds: 2), () {
        try {
          speakingFile.deleteSync();
        } catch (_) {}
      });
      _ttsTimers.add(clearTimer);
    });
    _ttsTimers.add(writeTimer);
  }

  void _spawnWanderProcess(String signalDir, String model) {
    if (_wanderChildren.length >= _maxChildren) {
      debugPrint('Max wander children reached ($_maxChildren), skipping spawn');
      return;
    }

    final exe = Platform.resolvedExecutable;
    final args = [
      '--wander',
      '--signal-dir', signalDir,
      '--model', model,
    ];
    // Pass models dir if specified
    if (widget.config.modelsDir != null) {
      args.addAll(['--models-dir', widget.config.modelsDir!]);
    }
    Process.start(exe, args, mode: ProcessStartMode.detached).then((process) {
      _wanderChildren.add(_WanderChild(pid: process.pid, signalDir: signalDir));
      _persistChildPids();
      debugPrint('Spawned wander mascot: pid=${process.pid} (${_wanderChildren.length}/$_maxChildren)');
    }).catchError((e) {
      debugPrint('Failed to spawn wander mascot: $e');
    });
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
    await windowManager.setSize(Size(width, _windowHeight));
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    for (final timer in _ttsTimers) {
      timer.cancel();
    }
    _ttsTimers.clear();
    // Dismiss and kill all wander child processes
    for (final child in _wanderChildren) {
      try {
        File('${child.signalDir}/mascot_dismiss').writeAsStringSync('');
        Process.killPid(child.pid);
      } catch (_) {}
    }
    _wanderChildren.clear();
    _persistChildPids(); // Write empty list (or overwrite stale data)
    // Clean up the file entirely since no children remain
    try {
      final signalDir = widget.config.signalDir ?? _defaultSignalDir();
      final childrenFile = File('$signalDir/wander_children.json');
      if (childrenFile.existsSync()) childrenFile.deleteSync();
    } catch (_) {}
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
          outlineEnabled: widget.config.outline,
        ),
      );
    }

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
            child: MascotWidget(
              controller: _controller,
              outlineEnabled: widget.config.outline,
            ),
          ),
          for (var i = 0; i < _children.length; i++)
            SizedBox(
              width: _childWidth,
              height: _windowHeight,
              child: MascotWidget(
                key: ValueKey(_children[i].signalDir),
                controller: _children[i].controller,
                outlineEnabled: widget.config.outline,
                onDismissComplete: () => _removeChildBySignalDir(_children[i].signalDir),
              ),
            ),
        ],
      ),
    );
  }
}
