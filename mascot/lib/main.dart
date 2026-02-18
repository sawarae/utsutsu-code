import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, FileSystemEvent, IOSink, Platform, Process, ProcessSignal, ProcessStartMode, exit;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'cut_in_overlay.dart';
import 'mascot_controller.dart';
import 'mascot_widget.dart';
import 'swarm/swarm_app.dart';
import 'wander_controller.dart';
import 'window_config.dart';

void main(List<String> args) async {
  final config = _parseArgs(args);
  final winConfig = WindowConfig.autoDetect();

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Swarm mode: fullscreen transparent overlay
  if (config.swarm) {
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final screenSize = primaryDisplay.size;

    final windowOptions = WindowOptions(
      size: screenSize,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      skipTaskbar: true,
      alwaysOnTop: true,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setBackgroundColor(Colors.transparent);
      if (Platform.isMacOS) {
        await windowManager.setClosable(false);
        await windowManager.setMinimizable(false);
        await windowManager.setMovable(false);
      }
      await windowManager.setSize(screenSize);
      await windowManager.setPosition(Offset.zero);
      await windowManager.show();
    });

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: SwarmApp(
        signalDir: config.signalDir ?? _defaultSignalDir(),
        config: winConfig,
        collisionEnabled: config.collision,
        modelsDir: config.modelsDir,
        model: config.model,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
      ),
    ));
    return;
  }

  // Cut-in mode: fullscreen dramatic overlay
  if (config.cutIn) {
    // Redirect debugPrint to a log file since detached process stdout is lost
    IOSink? cutInLogSink;
    if (config.signalDir != null) {
      final logFile = File('${config.signalDir}/cutin_debug.log');
      cutInLogSink = logFile.openWrite(mode: FileMode.append);
      debugPrint = (String? message, {int? wrapWidth}) {
        final ts = DateTime.now().toIso8601String();
        cutInLogSink!.writeln('[$ts] $message');
      };
      debugPrint('CutIn subprocess started');
    }
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final screenSize = primaryDisplay.size;

    final windowOptions = WindowOptions(
      size: screenSize,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      skipTaskbar: true,
      alwaysOnTop: true,
    );

    debugPrint('[CutIn] Screen size: $screenSize');

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      debugPrint('[CutIn] Window ready to show, configuring...');
      await windowManager.setBackgroundColor(Colors.transparent);
      if (Platform.isMacOS) {
        await windowManager.setClosable(false);
        await windowManager.setMinimizable(false);
        await windowManager.setMovable(false);
      }
      await windowManager.setIgnoreMouseEvents(true);
      await windowManager.setVisibleOnAllWorkspaces(true);
      await windowManager.show();
      // Set size/position AFTER show() to override macOS window state restoration
      await windowManager.setSize(screenSize);
      await windowManager.setPosition(Offset.zero);
      // Re-apply after a brief delay to defeat macOS frame restoration
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await windowManager.setSize(screenSize);
      await windowManager.setPosition(Offset.zero);
      await windowManager.focus();
      debugPrint('[CutIn] Window shown: size=$screenSize, pos=0,0');
    });

    final controller = MascotController(
      signalDir: config.signalDir,
      modelsDir: config.modelsDir,
      model: config.model,
    );

    final background = CutInBackground.fromName(config.cutInBackground)
        ?? CutInBackground.forEmotion(config.cutInEmotion);

    debugPrint('[CutIn] Starting app: message="${config.cutInMessage}", emotion=${config.cutInEmotion}, bg=$background');

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: CutInOverlay(
        message: config.cutInMessage ?? '',
        emotion: config.cutInEmotion ?? 'Joy',
        background: background,
        controller: controller,
        onComplete: () async {
          debugPrint('[CutIn] onComplete: closing window');
          await cutInLogSink?.flush();
          windowManager.close();
          Future.delayed(const Duration(seconds: 1), () => exit(0));
        },
      ),
    ));
    return;
  }

  // Wander mode uses a smaller window; extra width for outline dilation padding
  final defaultWidth = config.wander ? winConfig.wanderWidth : winConfig.mainWidth;
  final defaultHeight = config.wander ? winConfig.wanderHeight : winConfig.mainHeight;
  final windowSize =
      Size(config.width ?? defaultWidth, config.height ?? defaultHeight);
  final windowOptions = WindowOptions(
    size: windowSize,
    // On macOS, window_manager handles transparency via NSWindow.
    // On Windows, DwmExtendFrameIntoClientArea in C++ (flutter_window.cpp)
    // creates the glass region; Flutter must also set transparent background
    // so that alpha=0 pixels pass through to the DWM compositor.
    backgroundColor: Colors.transparent,
    // On Windows, skip setTitleBarStyle entirely to avoid DWM margin reset
    // that breaks DwmExtendFrameIntoClientArea transparency.
    titleBarStyle: Platform.isWindows ? null : TitleBarStyle.hidden,
    // Hide native traffic light buttons — use custom close button instead.
    // Wander mode also hides them (child mascots are closed by parent).
    windowButtonVisibility: false,
    skipTaskbar: false,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setBackgroundColor(Colors.transparent);

    // Hide traffic light buttons / system buttons in wander mode
    // Disable window-level dragging so Flutter GestureDetector handles it
    if (config.wander) {
      await windowManager.setClosable(false);
      await windowManager.setMinimizable(false);
      if (Platform.isMacOS) {
        await windowManager.setMovable(false);
      }
      // On Windows, native drag is disabled via mascot/native_drag channel
      // in MascotWidget.initState
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

  runApp(MascotApp(config: config, windowConfig: winConfig));
}

String _defaultSignalDir() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  return '$home/.claude/utsutsu-code';
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
  final bool swarm;
  final bool collision;
  final bool cutIn;
  final String? cutInMessage;
  final String? cutInEmotion;
  final String? cutInBackground;

  const _AppConfig({
    this.modelsDir,
    this.model,
    this.signalDir,
    this.offsetX,
    this.width,
    this.height,
    this.wander = false,
    this.outline = true,
    this.swarm = false,
    this.collision = true,
    this.cutIn = false,
    this.cutInMessage,
    this.cutInEmotion,
    this.cutInBackground,
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
  bool swarm = false;
  bool collision = true;
  bool cutIn = false;
  String? cutInMessage;
  String? cutInEmotion;
  String? cutInBackground;

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
      case '--swarm':
        swarm = true;
      case '--no-collision':
        collision = false;
      case '--cutin':
        cutIn = true;
      case '--cutin-message':
        if (i + 1 < args.length) cutInMessage = args[++i];
      case '--cutin-emotion':
        if (i + 1 < args.length) cutInEmotion = args[++i];
      case '--cutin-background':
        if (i + 1 < args.length) cutInBackground = args[++i];
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
    swarm: swarm,
    collision: collision,
    cutIn: cutIn,
    cutInMessage: cutInMessage,
    cutInEmotion: cutInEmotion,
    cutInBackground: cutInBackground,
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
  final WindowConfig windowConfig;

  const MascotApp({super.key, required this.config, required this.windowConfig});

  @override
  State<MascotApp> createState() => _MascotAppState();
}

class _MascotAppState extends State<MascotApp> with WindowListener {
  WindowConfig get _wc => widget.windowConfig;

  late final MascotController _controller;
  WanderController? _wanderController;
  final List<_ChildMascot> _children = [];
  final List<_WanderChild> _wanderChildren = [];
  Timer? _spawnTimer;
  Timer? _childReaper;
  StreamSubscription<FileSystemEvent>? _spawnWatcher;
  late final String _spawnSignalPath;
  late final String _cutInSignalPath;
  final List<Timer> _ttsTimers = [];
  _WanderChild? _swarmOverlay; // Single swarm overlay process
  _WanderChild? _cutInProcess; // Active cut-in overlay process
  bool _cleanedUp = false;

  @override
  void initState() {
    super.initState();
    _controller = MascotController(
      signalDir: widget.config.signalDir,
      modelsDir: widget.config.modelsDir,
      model: widget.config.model,
      pollIntervalMs: widget.config.wander ? 500 : 100,
    );

    if (widget.config.wander) {
      final wc = widget.windowConfig;
      final windowW = widget.config.width ?? wc.wanderWidth;
      final windowH = widget.config.height ?? wc.wanderHeight;
      _wanderController = WanderController(
        windowWidth: windowW,
        windowHeight: windowH,
        signalDir: widget.config.signalDir,
        config: widget.windowConfig,
      );
      _wanderController!.start();
    }

    // Resolve signal paths from the main signal directory
    final signalDir = widget.config.signalDir ?? _defaultSignalDir();
    _spawnSignalPath = '$signalDir/spawn_child';
    _cutInSignalPath = '$signalDir/cutin';

    // Clean up zombie wander children from a previous (crashed) parent
    if (!widget.config.wander) {
      _cleanStaleChildren();
    }

    // Intercept macOS close button (traffic light red ×) so that dispose()
    // cleanup actually runs before the process exits.  Without this, the OS
    // terminates the process immediately and child wander mascots become
    // zombies.  Only needed for the parent mascot (non-wander).
    if (!widget.config.wander) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }

    // Watch for child spawn signals (only in non-wander mode)
    if (!widget.config.wander) {
      _startSpawnWatcher();
      _startChildReaper();
    }
  }

  /// Periodically check if wander child processes are still alive.
  /// Removes dead entries from [_wanderChildren] so new spawns are allowed.
  void _startChildReaper() {
    _childReaper = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_wanderChildren.isEmpty) return;
      final before = _wanderChildren.length;
      _wanderChildren.removeWhere((child) {
        return !_isProcessAlive(child.pid);
      });
      if (_wanderChildren.length < before) {
        _persistChildPids();
        debugPrint('Reaped dead wander children: ${before - _wanderChildren.length} removed, ${_wanderChildren.length} remaining');
      }
    });
  }

  /// Check if a process is still alive, cross-platform.
  /// On macOS/Linux, sends SIGCONT (harmless no-op signal).
  /// On Windows, SIGCONT is not supported, so use SIGTERM with signal 0
  /// semantics: killPid returns false if the process doesn't exist.
  static bool _isProcessAlive(int pid) {
    if (Platform.isWindows) {
      // On Windows, Process.killPid only supports sigterm/sigkill.
      // Instead, try to open the process handle via a harmless kill(0)-like
      // check. killPid(pid, sigterm) would actually terminate it, so we
      // use a different approach: check if the dismiss signal was written.
      // Fallback: use Process.run to query tasklist.
      try {
        final result = Process.runSync(
          'tasklist',
          ['/FI', 'PID eq $pid', '/NH'],
        );
        return RegExp(r'\b' + pid.toString() + r'\b')
            .hasMatch(result.stdout.toString());
      } catch (_) {
        return true; // Assume alive on error to avoid premature reaping
      }
    }
    // macOS/Linux: SIGCONT is harmless and returns false if process is gone
    return Process.killPid(pid, ProcessSignal.sigcont);
  }

  /// Use FSEvents (macOS) / inotify (Linux) to watch for spawn_child file
  /// creation. Falls back to 200ms polling if watch() is unavailable.
  void _startSpawnWatcher() {
    final signalDir = widget.config.signalDir ?? _defaultSignalDir();
    final dir = Directory(signalDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // On Windows, Directory.watch() starts successfully but may not deliver
    // FileSystemEvent.create events reliably. Always use polling there.
    if (Platform.isWindows) {
      _startSpawnPolling();
      return;
    }

    try {
      _spawnWatcher = dir.watch(events: FileSystemEvent.create | FileSystemEvent.modify).listen((event) {
        if (event.path.endsWith('/spawn_child') || event.path.endsWith(r'\spawn_child')) {
          _checkSpawnSignal();
        }
        if (event.path.endsWith('/cutin') || event.path.endsWith(r'\cutin')) {
          _checkCutInSignal();
        }
      }, onError: (_) {
        // Fallback to polling on watch error
        _spawnWatcher?.cancel();
        _spawnWatcher = null;
        _startSpawnPolling();
      });
    } catch (_) {
      _startSpawnPolling();
    }

    // Check for signals that were written before the watcher was ready
    // (e.g. left over from a crash, or written during startup)
    _checkSpawnSignal();
    _checkCutInSignal();
  }

  void _startSpawnPolling() {
    _spawnTimer?.cancel();
    _spawnTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        _checkSpawnSignal();
        _checkCutInSignal();
      },
    );
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
            final name = p.basename(entity.path);
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

    // 3. Clean stale cutin_* directories from previous cut-in processes
    try {
      final parentDir = Directory(signalDir);
      if (parentDir.existsSync()) {
        for (final entity in parentDir.listSync()) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (!name.startsWith('cutin_')) continue;
            try {
              entity.deleteSync(recursive: true);
              debugPrint('Cleaned stale cutin dir: ${entity.path}');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to clean stale cutin dirs: $e');
    }

    // 4. Remove legacy _active_task_mascots tracking file
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

    // In swarm mode, don't consume the signal — just ensure the overlay
    // is running and let it handle all spawn signals directly.
    // Swarm overlay is not yet supported on Windows (fullscreen transparent
    // overlay requires additional DWM/layered-window work), so always use
    // individual wander child processes there.
    if (!Platform.isWindows && _wc.maxChildren > _wc.swarmThreshold) {
      if (_swarmOverlay == null) {
        _launchSwarmOverlay('blend_shape_mini');
      }
      return;
    }

    // Non-swarm mode: atomically claim the signal file
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

      // Unwrap envelope v1 or use legacy format directly
      final payload = json.containsKey('version')
          ? (json['payload'] as Map<String, dynamic>? ?? {})
          : json;
      final taskId = payload['task_id'] as String;
      final parentDir = widget.config.signalDir ?? _defaultSignalDir();
      final signalDir = '$parentDir/task-$taskId';

      // Parent creates dir (moved from hook)
      Directory(signalDir).createSync(recursive: true);

      // Parent cleans stale dismiss (moved from hook)
      final dismissFile = File('$signalDir/mascot_dismiss');
      if (dismissFile.existsSync()) dismissFile.deleteSync();

      _spawnWanderProcess(signalDir, 'blend_shape_mini');
      _sendDelayedTts(signalDir);
    } catch (e) {
      debugPrint('Failed to spawn child mascot: $e');
    }
  }

  /// Check for a cut-in signal file and launch the cut-in overlay process.
  ///
  /// Signal file format (JSON):
  /// ```json
  /// {"message": "デプロイ完了！", "emotion": "Joy", "background": "speed_lines"}
  /// ```
  void _checkCutInSignal() {
    final file = File(_cutInSignalPath);
    if (!file.existsSync()) {
      return;
    }
    debugPrint('[CutIn] Signal file detected: ${file.path}');

    // Don't launch another cut-in while one is active
    if (_cutInProcess != null && _isProcessAlive(_cutInProcess!.pid)) {
      debugPrint('[CutIn] Skipping: existing cut-in process still alive (pid=${_cutInProcess!.pid})');
      return;
    }

    // Atomically claim the signal file
    final claimedPath = '${_cutInSignalPath}_processing';
    try {
      file.renameSync(claimedPath);
    } catch (e) {
      debugPrint('[CutIn] Failed to claim signal file (already claimed?): $e');
      return;
    }

    try {
      final claimedFile = File(claimedPath);
      final content = claimedFile.readAsStringSync().trim();
      claimedFile.deleteSync();
      debugPrint('[CutIn] Signal content: $content');

      final json = jsonDecode(content) as Map<String, dynamic>;
      final payload = json.containsKey('version')
          ? (json['payload'] as Map<String, dynamic>? ?? {})
          : json;

      final message = (payload['message'] as String?) ?? '';
      final emotion = (payload['emotion'] as String?) ?? 'Joy';
      final background = payload['background'] as String?;

      debugPrint('[CutIn] Launching: message="$message", emotion=$emotion, background=$background');
      _launchCutIn(message: message, emotion: emotion, background: background);
    } catch (e) {
      debugPrint('[CutIn] Failed to process cut-in signal: $e');
    }
  }

  void _launchCutIn({
    required String message,
    required String emotion,
    String? background,
  }) {
    // Create an isolated signal directory for the cut-in subprocess
    // so it doesn't consume the parent's mascot_speaking file.
    final parentDir = widget.config.signalDir ?? _defaultSignalDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cutInSignalDir = '$parentDir/cutin_$timestamp';
    Directory(cutInSignalDir).createSync(recursive: true);

    final exe = Platform.resolvedExecutable;
    final args = [
      '--cutin',
      '--cutin-message', message,
      '--cutin-emotion', emotion,
      '--signal-dir', cutInSignalDir,
    ];
    if (background != null) {
      args.addAll(['--cutin-background', background]);
    }
    // Always pass resolved models dir so the subprocess can find the model
    // even if _defaultModelsDir() resolution differs in the detached process.
    final modelsDir = widget.config.modelsDir ?? _controller.modelConfig.modelDirPath;
    final resolvedModelsDir = Directory(modelsDir).parent.path;
    args.addAll(['--models-dir', resolvedModelsDir]);
    if (widget.config.model != null) {
      args.addAll(['--model', widget.config.model!]);
    }
    final exeDir = File(exe).parent.path;
    Process.start(exe, args,
        mode: ProcessStartMode.detached,
        workingDirectory: exeDir).then((process) {
      _cutInProcess = _WanderChild(pid: process.pid, signalDir: cutInSignalDir);
      debugPrint('[CutIn] Launched cut-in overlay: pid=${process.pid}, signalDir=$cutInSignalDir');
    }).catchError((e) {
      debugPrint('[CutIn] Failed to launch cut-in overlay: $e');
    });
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

  void _launchSwarmOverlay(String model) {
    final exe = Platform.resolvedExecutable;
    final parentDir = widget.config.signalDir ?? _defaultSignalDir();
    final args = [
      '--swarm',
      '--signal-dir', parentDir,
      '--model', model,
    ];
    if (widget.config.modelsDir != null) {
      args.addAll(['--models-dir', widget.config.modelsDir!]);
    }
    Process.start(exe, args, mode: ProcessStartMode.detached).then((process) {
      _swarmOverlay = _WanderChild(pid: process.pid, signalDir: parentDir);
      debugPrint('Launched swarm overlay: pid=${process.pid}');
    }).catchError((e) {
      debugPrint('Failed to launch swarm overlay: $e');
    });
  }

  void _spawnWanderProcess(String signalDir, String model) {
    if (_wanderChildren.length >= _wc.maxChildren) {
      debugPrint('Max wander children reached (${_wc.maxChildren}), skipping spawn');
      return;
    }

    final exe = Platform.resolvedExecutable;
    final args = [
      '--wander',
      '--no-outline',
      '--signal-dir', signalDir,
      '--model', model,
    ];
    // Pass models dir if specified
    if (widget.config.modelsDir != null) {
      args.addAll(['--models-dir', widget.config.modelsDir!]);
    }
    // Use the exe's directory as working directory so the child can find
    // its data/ folder (Flutter assets, config files, etc.).
    final exeDir = File(exe).parent.path;
    Process.start(exe, args,
        mode: ProcessStartMode.detached,
        workingDirectory: exeDir).then((process) {
      _wanderChildren.add(_WanderChild(pid: process.pid, signalDir: signalDir));
      _persistChildPids();
      debugPrint('Spawned wander mascot: pid=${process.pid} (${_wanderChildren.length}/${_wc.maxChildren})');
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
    final width = _wc.mainWidth + _wc.childWidth * _children.length;
    await windowManager.setSize(Size(width, _wc.mainHeight));
  }

  @override
  void onWindowClose() async {
    await _performCleanup();
    await windowManager.destroy();
  }

  /// Cleanup child processes, timers, and controllers.  Guarded against
  /// double invocation (onWindowClose runs first, then dispose may follow).
  Future<void> _performCleanup() async {
    if (_cleanedUp) return;
    _cleanedUp = true;

    _spawnTimer?.cancel();
    _spawnWatcher?.cancel();
    _childReaper?.cancel();
    for (final timer in _ttsTimers) {
      timer.cancel();
    }
    _ttsTimers.clear();
    // Kill swarm overlay process
    if (_swarmOverlay != null) {
      try {
        Process.killPid(_swarmOverlay!.pid);
      } catch (_) {}
      _swarmOverlay = null;
    }
    // Kill cut-in overlay process and clean up its signal directory
    if (_cutInProcess != null) {
      try {
        Process.killPid(_cutInProcess!.pid);
      } catch (_) {}
      if (_cutInProcess!.signalDir.isNotEmpty) {
        try {
          Directory(_cutInProcess!.signalDir).deleteSync(recursive: true);
        } catch (_) {}
      }
      _cutInProcess = null;
    }
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
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _performCleanup();
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
            width: _wc.mainWidth,
            height: _wc.mainHeight,
            child: MascotWidget(
              controller: _controller,
              outlineEnabled: widget.config.outline,
            ),
          ),
          for (var i = 0; i < _children.length; i++)
            SizedBox(
              width: _wc.childWidth,
              height: _wc.mainHeight,
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
