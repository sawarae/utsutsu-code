import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../mascot_controller.dart';
import '../mascot_widget.dart';
import '../model_config.dart';
import '../window_config.dart';
import 'mascot_entity.dart';
import 'signal_monitor.dart';
import 'sprite_cache.dart';
import 'swarm_painter.dart';
import 'swarm_simulation.dart';

/// Entry point widget for the swarm overlay window.
///
/// A single fullscreen transparent window that renders all wander mascots.
/// Uses LOD (Level of Detail):
/// - LOD1: All entities drawn as pre-cached sprites via [SwarmPainter]
/// - LOD0: The active entity (dragged/tapped/speaking) rendered as full [MascotWidget]
class SwarmApp extends StatefulWidget {
  final String signalDir;
  final WindowConfig config;
  final bool collisionEnabled;
  final String? modelsDir;
  final String? model;
  final double screenWidth;
  final double screenHeight;

  const SwarmApp({
    super.key,
    required this.signalDir,
    required this.config,
    required this.screenWidth,
    required this.screenHeight,
    this.collisionEnabled = true,
    this.modelsDir,
    this.model,
  });

  @override
  State<SwarmApp> createState() => _SwarmAppState();
}

class _SwarmAppState extends State<SwarmApp> with TickerProviderStateMixin {
  static const _swarmModeChannel = MethodChannel('mascot/swarm_mode');
  static const _windowReadyChannel = MethodChannel('mascot/window_ready');

  late final SwarmSimulation _simulation;
  late final SpriteCache _spriteCache;
  late final SignalMonitor _signalMonitor;

  int? _activeEntityIndex;
  MascotController? _activeMascotController;
  Timer? _lod0DemoteTimer;

  StreamSubscription<FileSystemEvent>? _spawnWatcher;
  Timer? _spawnPollingTimer;
  late final String _spawnSignalPath;
  final List<Timer> _ttsTimers = [];

  double get _entityWidth => widget.config.wanderWidth;
  double get _entityHeight => widget.config.wanderHeight;

  @override
  void initState() {
    super.initState();

    _spawnSignalPath = '${widget.signalDir}/spawn_child';

    _simulation = SwarmSimulation(
      vsync: this,
      config: widget.config,
      screenWidth: widget.screenWidth,
      screenHeight: widget.screenHeight,
      entityWidth: _entityWidth,
      entityHeight: _entityHeight,
      collisionEnabled: widget.collisionEnabled,
    );

    _spriteCache = SpriteCache();

    _signalMonitor = SignalMonitor(
      pollIntervalMs: widget.config.signalPollMs,
      onSpeech: _onEntitySpeech,
      onSpeechEnd: _onEntitySpeechEnd,
      onDismiss: _onEntityDismiss,
    );

    _init();
  }

  Future<void> _init() async {
    // Prebake sprites
    final modelConfig = ModelConfig.fromEnvironment(
      modelsDir: widget.modelsDir,
      model: widget.model ?? 'blend_shape_mini',
    );
    await _spriteCache.prebake(modelConfig, _entityWidth, _entityHeight);

    // Start simulation
    _simulation.start();

    // Start signal monitoring
    _signalMonitor.start(_simulation.entities);

    // Watch for spawn signals
    _startSpawnWatcher();

    // Enable swarm mode on the native side
    if (Platform.isMacOS) {
      _swarmModeChannel.invokeMethod('setEnabled', true);
    }

    // Signal native window visibility
    _windowReadyChannel.invokeMethod('show');

    // Start entity rect updates for click-through
    _startEntityRectUpdates();

    if (mounted) setState(() {});
  }

  void _startEntityRectUpdates() {
    // Push entity rects to native side every 100ms for click-through
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _pushEntityRects();
    });
  }

  void _pushEntityRects() {
    if (!Platform.isMacOS) return;
    final rects = _simulation.entities
        .where((e) => !e.dismissed)
        .map((e) => {
              'x': e.x,
              'y': e.y + e.bounceOffset,
              'w': _entityWidth,
              'h': _entityHeight,
            })
        .toList();
    _swarmModeChannel.invokeMethod('updateEntityRects', rects);
  }

  // --- Spawn watching ---

  void _startSpawnWatcher() {
    final dir = Directory(widget.signalDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    try {
      _spawnWatcher = dir.watch(events: FileSystemEvent.create).listen((event) {
        if (event.path.endsWith('/spawn_child')) {
          _checkSpawnSignal();
        }
      }, onError: (_) {
        _spawnWatcher?.cancel();
        _spawnWatcher = null;
        _startSpawnPolling();
      });
    } catch (_) {
      _startSpawnPolling();
    }
  }

  void _startSpawnPolling() {
    _spawnPollingTimer?.cancel();
    _spawnPollingTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _checkSpawnSignal(),
    );
  }

  void _checkSpawnSignal() {
    final file = File(_spawnSignalPath);
    if (!file.existsSync()) return;

    final claimedPath = '${_spawnSignalPath}_processing';
    try {
      file.renameSync(claimedPath);
    } catch (_) {
      return;
    }

    try {
      final claimedFile = File(claimedPath);
      final content = claimedFile.readAsStringSync().trim();
      claimedFile.deleteSync();

      final json = jsonDecode(content) as Map<String, dynamic>;
      final payload = json.containsKey('version')
          ? (json['payload'] as Map<String, dynamic>? ?? {})
          : json;
      final taskId = payload['task_id'] as String;
      final signalDir = '${widget.signalDir}/task-$taskId';

      Directory(signalDir).createSync(recursive: true);
      final dismissFile = File('$signalDir/mascot_dismiss');
      if (dismissFile.existsSync()) dismissFile.deleteSync();

      // Add entity to swarm
      final entity = _simulation.addEntity(signalDir: signalDir);

      // Restart signal monitor with updated entity list
      _signalMonitor.start(_simulation.entities);

      // Send delayed TTS
      _sendDelayedTts(signalDir);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('SwarmApp: failed to spawn entity: $e');
    }
  }

  void _sendDelayedTts(String signalDir) {
    final writeTimer = Timer(const Duration(seconds: 2), () {
      final speakingFile = File('$signalDir/mascot_speaking');
      try {
        speakingFile.writeAsStringSync(
          jsonEncode({'message': 'タスク開始します', 'emotion': 'Gentle'}),
        );
      } catch (_) {
        return;
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

  // --- LOD0 management ---

  void _promoteToLod0(int index) {
    if (_activeEntityIndex == index) return;

    _demoteFromLod0();

    _activeEntityIndex = index;
    final entity = _simulation.entities[index];

    _activeMascotController = MascotController(
      signalDir: entity.signalDir,
      modelsDir: widget.modelsDir,
      model: widget.model ?? 'blend_shape_mini',
      pollIntervalMs: 100,
    );

    // Apply entity's wander overrides
    _activeMascotController!.setWanderOverrides(entity.parameterOverrides);

    _scheduleLod0Demotion();
    if (mounted) setState(() {});
  }

  void _demoteFromLod0() {
    _lod0DemoteTimer?.cancel();
    _lod0DemoteTimer = null;

    if (_activeMascotController != null) {
      _activeMascotController!.dispose();
      _activeMascotController = null;
    }
    _activeEntityIndex = null;
  }

  void _scheduleLod0Demotion() {
    _lod0DemoteTimer?.cancel();
    _lod0DemoteTimer = Timer(
      Duration(milliseconds: widget.config.lod0TimeoutMs),
      () {
        _demoteFromLod0();
        if (mounted) setState(() {});
      },
    );
  }

  // --- Signal callbacks ---

  void _onEntitySpeech(MascotEntity entity, String message, String? emotion) {
    final index = _simulation.entities.indexOf(entity);
    if (index >= 0) {
      _promoteToLod0(index);
      if (_activeMascotController != null && emotion != null) {
        _activeMascotController!.showExpression(emotion, message);
      }
      _scheduleLod0Demotion();
    }
    if (mounted) setState(() {});
  }

  void _onEntitySpeechEnd(MascotEntity entity) {
    if (_activeEntityIndex != null &&
        _simulation.entities.indexOf(entity) == _activeEntityIndex) {
      _activeMascotController?.hideExpression();
      _scheduleLod0Demotion();
    }
    if (mounted) setState(() {});
  }

  void _onEntityDismiss(MascotEntity entity) {
    final index = _simulation.entities.indexOf(entity);
    if (index == _activeEntityIndex) {
      _demoteFromLod0();
    }
    _simulation.removeEntity(entity);

    // Clean up signal directory
    try {
      final dir = Directory(entity.signalDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}

    if (mounted) setState(() {});
  }

  // --- Drag handling ---

  int? _findEntityAt(Offset position) {
    // Search in reverse order (top entities first)
    for (var i = _simulation.entities.length - 1; i >= 0; i--) {
      final e = _simulation.entities[i];
      if (e.dismissed) continue;
      if (position.dx >= e.x &&
          position.dx <= e.x + _entityWidth &&
          position.dy >= e.y + e.bounceOffset &&
          position.dy <= e.y + e.bounceOffset + _entityHeight) {
        return i;
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    final index = _findEntityAt(details.localPosition);
    if (index == null) return;
    _promoteToLod0(index);
    _simulation.startDrag(_simulation.entities[index]);
    _lod0DemoteTimer?.cancel(); // Don't demote during drag
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeEntityIndex == null) return;
    _simulation.updateDrag(
      _simulation.entities[_activeEntityIndex!],
      details.delta.dx,
      details.delta.dy,
    );
  }

  void _onPanEnd(DragEndDetails details) {
    if (_activeEntityIndex == null) return;
    _simulation.endDrag(_simulation.entities[_activeEntityIndex!]);
    _scheduleLod0Demotion();
  }

  @override
  void dispose() {
    _lod0DemoteTimer?.cancel();
    _spawnWatcher?.cancel();
    _spawnPollingTimer?.cancel();
    for (final timer in _ttsTimers) {
      timer.cancel();
    }
    _ttsTimers.clear();

    // Dismiss all entities
    for (final e in _simulation.entities) {
      try {
        File('${e.signalDir}/mascot_dismiss').writeAsStringSync('');
      } catch (_) {}
    }

    _signalMonitor.dispose();
    _activeMascotController?.dispose();
    _simulation.dispose();
    _spriteCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // LOD1: All sprites via CustomPaint
            Positioned.fill(
              child: CustomPaint(
                painter: SwarmPainter(
                  simulation: _simulation,
                  sprites: _spriteCache,
                  activeEntityIndex: _activeEntityIndex,
                ),
              ),
            ),
            // LOD0: Active entity as full PuppetWidget
            if (_activeEntityIndex != null &&
                _activeEntityIndex! < _simulation.entities.length &&
                _activeMascotController != null)
              ListenableBuilder(
                listenable: _simulation,
                builder: (context, _) {
                  final entity = _simulation.entities[_activeEntityIndex!];
                  final (sx, sy) = entity.squishScale;
                  return Positioned(
                    left: entity.x,
                    top: entity.y + entity.bounceOffset,
                    child: Transform.scale(
                      scaleX: sx,
                      scaleY: sy,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: _entityWidth,
                        height: _entityHeight,
                        child: entity.facingLeft
                            ? MascotWidget(
                                controller: _activeMascotController!,
                                outlineEnabled: false,
                                renderWidth: _entityWidth,
                              )
                            : Transform.flip(
                                flipX: true,
                                child: MascotWidget(
                                  controller: _activeMascotController!,
                                  outlineEnabled: false,
                                  renderWidth: _entityWidth,
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            // Entity count debug overlay (only in debug mode)
            if (false) // Set to true for debugging
              Positioned(
                top: 10,
                right: 10,
                child: ListenableBuilder(
                  listenable: _simulation,
                  builder: (context, _) {
                    return Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black54,
                      child: Text(
                        'Entities: ${_simulation.entities.length}\n'
                        'Collisions: ${_simulation.lastCollisionCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
