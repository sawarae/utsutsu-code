import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../window_config.dart';
import 'collision_grid.dart';
import 'mascot_entity.dart';

/// Single-ticker simulation that drives all swarm entities.
///
/// One Ticker, one notifyListeners() per frame, zero file I/O per tick.
class SwarmSimulation extends ChangeNotifier {
  final List<MascotEntity> entities = [];
  final WindowConfig config;
  double screenWidth;
  double screenHeight;
  final double entityWidth;
  final double entityHeight;
  final bool collisionEnabled;
  final double bottomMargin;

  late final Ticker _ticker;
  late final CollisionGrid _grid;
  final Random _rng = Random();
  Duration _lastElapsed = Duration.zero;
  int _lastNotifyMs = 0;
  int _collisionSkipCounter = 0;

  /// Number of collisions resolved in the last tick (for debugging).
  int lastCollisionCount = 0;

  SwarmSimulation({
    required TickerProvider vsync,
    required this.config,
    required this.screenWidth,
    required this.screenHeight,
    required this.entityWidth,
    required this.entityHeight,
    this.collisionEnabled = true,
    this.bottomMargin = 0,
  }) {
    _grid = CollisionGrid(
      cellSize: entityWidth,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      entityWidth: entityWidth,
      entityHeight: entityHeight,
    );
    _ticker = vsync.createTicker(_onTick);
  }

  void start() {
    _ticker.start();
  }

  /// Add a new entity at a random position, starting with a drop animation.
  MascotEntity addEntity({required String signalDir}) {
    final x = _rng.nextDouble() * (screenWidth - entityWidth);
    final entity = MascotEntity(
      x: x,
      y: -entityHeight,
      speed: _randomSpeed(),
      signalDir: signalDir,
      facingLeft: _rng.nextBool(),
      isDropping: true,
      dropVelX: (_rng.nextDouble() - 0.5) * 6.0,
      dropVelY: 0,
      reverseCountdown: _randomReverseDelay(),
      sparkleCountdown: _randomSparkleDelay(),
      armCountdown: _randomArmDelay(),
    );
    entity.facingLeft = entity.dropVelX < 0;
    entities.add(entity);
    return entity;
  }

  void removeEntity(MascotEntity entity) {
    entities.remove(entity);
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    // Skip if frame took too long (e.g., app was backgrounded)
    if (dt.inMilliseconds > 100) return;

    final bottomY = screenHeight - entityHeight + bottomMargin;

    // 1. Update all entity positions
    for (final e in entities) {
      if (e.dismissed) continue;

      if (e.isDropping) {
        _updateDrop(e, bottomY);
        continue;
      }

      if (e.isInertia) {
        _updateInertia(e, bottomY);
        continue;
      }

      if (e.isDragging || e.isPaused) {
        _updateTimers(e);
        continue;
      }

      _updateMovement(e, bottomY);
      _updateBounce(e, elapsed);
      _updateTimers(e);
    }

    // 2. Collision detection (if enabled), throttled to ~20Hz
    if (collisionEnabled && ++_collisionSkipCounter >= 3) {
      _collisionSkipCounter = 0;
      _grid.clear();
      for (final e in entities) {
        if (!e.isDragging && !e.isDropping && !e.dismissed) {
          _grid.insert(e);
        }
      }
      lastCollisionCount = _grid.resolveCollisions();
    }

    // 3. Throttle repaints to ~30fps; skip if no entities
    if (entities.isEmpty) return;
    final nowMs = elapsed.inMilliseconds;
    if (nowMs - _lastNotifyMs < 33) return;
    _lastNotifyMs = nowMs;
    notifyListeners();
  }

  void _updateDrop(MascotEntity e, double bottomY) {
    e.dropVelY += config.gravity;
    e.dropVelX *= config.friction;
    e.x += e.dropVelX;
    e.y += e.dropVelY;

    // Bounce off horizontal edges
    if (e.x <= 0) {
      e.x = 0;
      e.dropVelX = -e.dropVelX * 0.5;
    } else if (e.x >= screenWidth - entityWidth) {
      e.x = screenWidth - entityWidth;
      e.dropVelX = -e.dropVelX * 0.5;
    }

    if (e.y >= bottomY) {
      e.y = bottomY;
      e.dropVelY = -e.dropVelY * config.bounceDamping;
      e.bounceCount++;

      if (e.bounceCount >= 3 || e.dropVelY.abs() < 1.0) {
        e.isDropping = false;
        e.y = bottomY;
        e.isPaused = false;
      }
    }
  }

  void _updateMovement(MascotEntity e, double bottomY) {
    final dx = (e.facingLeft ? -e.speed : e.speed) * e.speedMultiplier;
    e.x += dx;

    if (e.x <= 0) {
      e.x = 0;
      _startReverse(e, goLeft: false);
      return;
    }
    if (e.x >= screenWidth - entityWidth) {
      e.x = screenWidth - entityWidth;
      _startReverse(e, goLeft: true);
      return;
    }
  }

  void _updateBounce(MascotEntity e, Duration elapsed) {
    final ms = elapsed.inMilliseconds % config.bouncePeriodMs;
    final newPhase = (ms / config.bouncePeriodMs) * 2 * pi;
    // Skip if change is negligible
    if ((newPhase - e.bouncePhase).abs() < 0.1) return;
    e.bouncePhase = newPhase;
  }

  void _updateTimers(MascotEntity e) {
    // Reverse countdown
    if (!e.isPaused && !e.isDragging && !e.isDropping && !e.isInertia) {
      e.reverseCountdown--;
      if (e.reverseCountdown <= 0) {
        _startReverse(e, goLeft: !e.facingLeft);
      }
    }

    // Sparkle countdown
    if (e.sparklesActive) {
      e.sparkleOffCountdown--;
      if (e.sparkleOffCountdown <= 0) {
        e.sparklesActive = false;
        e.sparkleCountdown = _randomSparkleDelay();
      }
    } else {
      e.sparkleCountdown--;
      if (e.sparkleCountdown <= 0) {
        e.sparklesActive = true;
        e.sparkleOffCountdown = config.sparkleDurationMs ~/ 33;
      }
    }

    // Arm switch countdown
    e.armCountdown--;
    if (e.armCountdown <= 0) {
      final states = ['empty', 'broom', 'luggage'];
      e.armState = states[_rng.nextInt(states.length)];
      e.armCountdown = _randomArmDelay();
    }
  }

  void _startReverse(MascotEntity e, {required bool goLeft}) {
    e.isPaused = true;
    // Simple pause-and-reverse: will be unpaused on next countdown
    e.facingLeft = goLeft;
    e.speed = _randomSpeed();
    // Short pause in ticks (~6 ticks = ~200ms at 33ms/tick)
    // After 6 ticks isPaused is already set, movement will resume when
    // _updateTimers decrements reverseCountdown to trigger next reverse
    e.reverseCountdown = 6; // ~200ms pause
    // Schedule unpause
    Future.delayed(Duration(milliseconds: 200 + _rng.nextInt(300)), () {
      e.isPaused = false;
      e.speedMultiplier = 1.0;
      e.reverseCountdown = _randomReverseDelay();
    });
  }

  void _updateInertia(MascotEntity e, double bottomY) {
    e.velocityX *= config.inertiaFriction;
    e.velocityY *= config.inertiaFriction;
    e.velocityY += config.inertiaGravity;
    e.x += e.velocityX;
    e.y += e.velocityY;

    // Bounce off horizontal edges
    if (e.x <= 0) {
      e.x = 0;
      e.velocityX = -e.velocityX * 0.5;
    } else if (e.x >= screenWidth - entityWidth) {
      e.x = screenWidth - entityWidth;
      e.velocityX = -e.velocityX * 0.5;
    }

    // Bounce off top
    if (e.y < 0) {
      e.y = 0;
      e.velocityY = -e.velocityY * 0.5;
    }

    // Settle at bottom
    if (e.y >= bottomY) {
      e.y = bottomY;
      e.velocityY = 0;
    }

    // Stop when velocity is negligible and at bottom
    if (e.velocityX.abs() < 0.1 &&
        e.velocityY.abs() < 0.1 &&
        (e.y - bottomY).abs() < 1) {
      e.y = bottomY;
      e.isInertia = false;
      e.isPaused = false;
      e.reverseCountdown = _randomReverseDelay();
    }
  }

  // --- Drag support ---

  void startDrag(MascotEntity e) {
    e.isDragging = true;
    e.isInertia = false;
    e.isPaused = true;
    e.bouncePhase = 0;
    e.dragSamples.clear();
  }

  void updateDrag(MascotEntity e, double dx, double dy) {
    e.x += dx;
    e.y += dy;
    e.x = e.x.clamp(0.0, screenWidth - entityWidth);
    e.y = e.y.clamp(0.0, screenHeight - entityHeight + bottomMargin);

    final now = DateTime.now().millisecondsSinceEpoch;
    e.dragSamples.add((now, e.x, e.y));
    if (e.dragSamples.length > 5) e.dragSamples.removeAt(0);
  }

  void endDrag(MascotEntity e) {
    e.isDragging = false;

    // Compute velocity from drag samples
    if (e.dragSamples.length >= 2) {
      final first = e.dragSamples.first;
      final last = e.dragSamples.last;
      final dtMs = last.$1 - first.$1;
      if (dtMs > 0) {
        e.velocityX = (last.$2 - first.$2) / dtMs * 1000 / 30;
        e.velocityY = (last.$3 - first.$3) / dtMs * 1000 / 30;
      }
    }
    e.dragSamples.clear();

    if (e.velocityX.abs() > 0.5) {
      e.facingLeft = e.velocityX < 0;
    }

    e.isInertia = true;
  }

  // --- Random value generators ---

  double _randomSpeed() {
    return config.speedMin + _rng.nextDouble() * (config.speedMax - config.speedMin);
  }

  int _randomReverseDelay() {
    final ms = config.reverseDelayMinMs +
        _rng.nextInt(config.reverseDelayMaxMs - config.reverseDelayMinMs + 1);
    return ms ~/ 33; // Convert to ticks
  }

  int _randomSparkleDelay() {
    final ms = config.sparkleDelayMinMs +
        _rng.nextInt(config.sparkleDelayMaxMs - config.sparkleDelayMinMs + 1);
    return ms ~/ 33;
  }

  int _randomArmDelay() {
    final ms = config.armDelayMinMs +
        _rng.nextInt(config.armDelayMaxMs - config.armDelayMinMs + 1);
    return ms ~/ 33;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
