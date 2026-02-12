import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math';

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Controls the wander behaviour of a mini mascot character.
///
/// Moves the window horizontally along the bottom of the screen at a gentle
/// pace, with periodic direction reversals, bouncing, squishy deformation,
/// sparkle effects and random arm/item switching.
class WanderController extends ChangeNotifier {
  final Random _rng;
  final double windowWidth;
  final double windowHeight;
  final String? signalDir;

  // --- Movement state ---
  double _x = 0;
  double _y = 0;
  double _screenWidth = 1920;
  double _screenHeight = 1080;
  bool _facingLeft = false;
  bool _isPaused = false;
  double _speed; // px per tick (~30fps)
  Timer? _moveTimer;

  // --- Reverse scheduling ---
  Timer? _reverseTimer;
  Timer? _pauseTimer;
  Timer? _decelerationTimer;
  double _speedMultiplier = 1.0;

  // --- Drop entrance ---
  Timer? _dropTimer;

  // --- Drag state ---
  bool _isDragging = false;
  double _velocityX = 0;
  double _velocityY = 0;
  Timer? _inertiaTimer;
  // Manual velocity tracking (Flutter reports 0 when window moves with finger)
  final List<(int, double, double)> _dragSamples = []; // (ms, x, y)

  // --- Bounce ---
  late final Ticker _bounceTicker;
  double _bouncePhase = 0; // 0..2*pi
  static const _bouncePeriodMs = 600;
  static const _bounceHeight = 6.0;

  // --- Sparkles ---
  bool _sparklesActive = false;
  Timer? _sparkleOnTimer;
  Timer? _sparkleOffTimer;

  // --- Arm/item ---
  String _armState = 'luggage'; // 'empty' | 'broom' | 'luggage'
  Timer? _armTimer;

  // --- Collision ---
  int _tickCount = 0;
  static const _collisionCheckInterval = 6; // every ~200ms at 30fps
  DateTime? _lastCollisionTime;
  static const _collisionCooldown = Duration(seconds: 5);
  bool _writingPosition = false;

  /// Called when a collision occurs (after cooldown).
  VoidCallback? onCollision;

  // --- Public getters ---
  bool get facingLeft => _facingLeft;
  double get bounceOffset => _isPaused ? 0 : -_bounceHeight * sin(_bouncePhase);
  bool get sparklesActive => _sparklesActive;
  String get armState => _armState;
  bool get isPaused => _isPaused;
  bool get isDragging => _isDragging;
  double get positionX => _x;
  double get positionY => _y;

  /// Squish scale factors for the "mochi" deformation effect.
  ///
  /// At the top of the bounce, the character is slightly taller and narrower.
  /// At the bottom, it's shorter and wider.
  /// Returns (scaleX, scaleY).
  (double, double) get squishScale {
    if (_isPaused) return (1.0, 1.0);
    final t = sin(_bouncePhase);
    final sx = 1.0 - 0.03 * t;
    final sy = 1.0 + 0.03 * t;
    return (sx, sy);
  }

  /// Parameter overrides to apply on top of MascotController's emotion state.
  Map<String, double> get parameterOverrides {
    final m = <String, double>{};
    if (_sparklesActive) {
      m['Sparkles'] = 1.0;
    }
    switch (_armState) {
      case 'broom':
        m['Arm_Empty'] = 0.0;
        m['Arm_Broom'] = 1.0;
        m['Arm_Luggage'] = 0.0;
      case 'luggage':
        m['Arm_Empty'] = 0.0;
        m['Arm_Broom'] = 0.0;
        m['Arm_Luggage'] = 1.0;
      default:
        m['Arm_Empty'] = 1.0;
        m['Arm_Broom'] = 0.0;
        m['Arm_Luggage'] = 0.0;
    }
    return m;
  }

  WanderController({
    int? seed,
    this.windowWidth = 150,
    this.windowHeight = 350,
    this.signalDir,
  }) : _rng = Random(seed),
       _speed = 0 {
    _speed = _randomSpeed();
    _bounceTicker = Ticker(_onBounceTick);
  }

  /// Initialise and start wandering. Call once after construction.
  Future<void> start() async {
    // Determine screen dimensions
    final display = await screenRetriever.getPrimaryDisplay();
    _screenWidth = display.size.width;
    _screenHeight = display.size.height;

    // Start at a random X within the screen
    _x = _rng.nextDouble() * (_screenWidth - windowWidth);
    _facingLeft = _rng.nextBool();

    // Start above the screen and drop down
    _y = -windowHeight;
    _isPaused = true;
    await windowManager.setPosition(Offset(_x, _y));

    // Drop entrance: gravity pulls the mascot to the bottom
    _startDrop();

    // Schedule sparkle and arm switch immediately (visual-only, no movement)
    _scheduleSparkle();
    _scheduleArmSwitch();
  }

  /// Animate the mascot falling from the top of the screen with gravity
  /// and a small bounce on landing, then start normal wandering.
  void _startDrop() {
    double velY = 0;
    // Random horizontal drift: -3.0 to +3.0 px/tick, matching facing direction
    double velX = (_rng.nextDouble() - 0.5) * 6.0;
    _facingLeft = velX < 0;
    const gravity = 0.8;
    const bounceDamping = 0.4;
    const friction = 0.98;
    const bottomMargin = 50.0;
    final bottomY = _screenHeight - windowHeight + bottomMargin;
    var bounceCount = 0;

    _dropTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      velY += gravity;
      velX *= friction;
      _x += velX;
      _y += velY;

      // Bounce off horizontal edges
      if (_x <= 0) {
        _x = 0;
        velX = -velX * 0.5;
      } else if (_x >= _screenWidth - windowWidth) {
        _x = _screenWidth - windowWidth;
        velX = -velX * 0.5;
      }

      if (_y >= bottomY) {
        _y = bottomY;
        velY = -velY * bounceDamping;
        bounceCount++;

        // Stop after 3 bounces or negligible velocity
        if (bounceCount >= 3 || velY.abs() < 1.0) {
          timer.cancel();
          _dropTimer = null;
          _y = bottomY;
          _isPaused = false;

          // Start normal wandering
          _bounceTicker.start();
          _moveTimer = Timer.periodic(
            const Duration(milliseconds: 33),
            (_) => _tick(),
          );
          _scheduleReverse();
          notifyListeners();
          return;
        }
      }

      _updateWindowPosition();
      notifyListeners();
    });
  }

  double _randomSpeed() {
    // 0.4 to 1.2 px per tick (33ms) → 12 to 36 px/sec
    return 0.4 + _rng.nextDouble() * 0.8;
  }

  void _tick() {
    if (_isPaused) return;

    // Move (scaled by deceleration/acceleration multiplier)
    final dx = (_facingLeft ? -_speed : _speed) * _speedMultiplier;
    _x += dx;

    // Clamp and bounce off edges
    if (_x <= 0) {
      _x = 0;
      _startPause(goLeft: false);
      return;
    }
    if (_x >= _screenWidth - windowWidth) {
      _x = _screenWidth - windowWidth;
      _startPause(goLeft: true);
      return;
    }

    // Periodically broadcast position and check collisions
    _tickCount++;
    if (_tickCount % _collisionCheckInterval == 0) {
      _broadcastPosition();
      _checkCollisions();
    }

    _updateWindowPosition();
  }

  void _updateWindowPosition() async {
    try {
      await windowManager.setPosition(Offset(_x, _y));
    } catch (_) {}
  }

  void _onBounceTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds % _bouncePeriodMs;
    _bouncePhase = (ms / _bouncePeriodMs) * 2 * pi;
    notifyListeners();
  }

  // --- Direction reversal ---

  void _scheduleReverse() {
    _reverseTimer?.cancel();
    // 5 to 15 seconds
    final delayMs = 5000 + _rng.nextInt(10001);
    _reverseTimer = Timer(Duration(milliseconds: delayMs), () {
      _startPause(goLeft: !_facingLeft);
    });
  }

  void _startPause({required bool goLeft}) {
    _reverseTimer?.cancel();
    _decelerationTimer?.cancel();
    _pauseTimer?.cancel();

    // Phase 1: Decelerate over ~200ms (6 steps × 33ms)
    const steps = 6;
    var step = 0;
    _decelerationTimer = Timer.periodic(const Duration(milliseconds: 33), (
      timer,
    ) {
      step++;
      _speedMultiplier = (1.0 - step / steps).clamp(0.0, 1.0);
      notifyListeners();
      if (step >= steps) {
        timer.cancel();
        _isPaused = true;
        notifyListeners();

        // Phase 2: Brief pause (200-500ms)
        final pauseMs = 200 + _rng.nextInt(301);
        _pauseTimer = Timer(Duration(milliseconds: pauseMs), () {
          _facingLeft = goLeft;
          _speed = _randomSpeed();
          _isPaused = false;

          // Phase 3: Accelerate over ~200ms
          var accelStep = 0;
          _decelerationTimer = Timer.periodic(
            const Duration(milliseconds: 33),
            (timer) {
              accelStep++;
              _speedMultiplier = (accelStep / steps).clamp(0.0, 1.0);
              notifyListeners();
              if (accelStep >= steps) {
                timer.cancel();
                _speedMultiplier = 1.0;
                notifyListeners();
              }
            },
          );

          notifyListeners();
          _scheduleReverse();
        });
      }
    });
  }

  // --- Sparkles ---

  void _scheduleSparkle() {
    _sparkleOnTimer?.cancel();
    // 8 to 20 seconds
    final delayMs = 8000 + _rng.nextInt(12001);
    _sparkleOnTimer = Timer(Duration(milliseconds: delayMs), () {
      _sparklesActive = true;
      notifyListeners();

      // Last 3 seconds
      _sparkleOffTimer?.cancel();
      _sparkleOffTimer = Timer(const Duration(seconds: 3), () {
        _sparklesActive = false;
        notifyListeners();
        _scheduleSparkle();
      });
    });
  }

  // --- Drag support ---

  /// Called when drag starts. Pauses autonomous movement and animation.
  void startDrag() {
    _isDragging = true;
    _dragSamples.clear();
    _dropTimer?.cancel();
    _moveTimer?.cancel();
    _reverseTimer?.cancel();
    _pauseTimer?.cancel();
    _decelerationTimer?.cancel();
    _inertiaTimer?.cancel();
    _bounceTicker.stop();
    _bouncePhase = 0;
    _isPaused = true;
    notifyListeners();
  }

  /// Called during drag. Updates window position by delta.
  void updateDrag(Offset delta) {
    _x += delta.dx;
    _y += delta.dy;
    _x = _x.clamp(0.0, _screenWidth - windowWidth);
    _y = _y.clamp(0.0, _screenHeight - windowHeight);

    // Record sample for manual velocity estimation
    final now = DateTime.now().millisecondsSinceEpoch;
    _dragSamples.add((now, _x, _y));
    if (_dragSamples.length > 5) _dragSamples.removeAt(0);

    _updateWindowPosition();
  }

  /// Called when drag ends. Computes velocity from recent drag samples
  /// and applies inertia physics.
  void endDrag() {
    _isDragging = false;
    _inertiaTimer?.cancel();

    // Compute velocity from recent position samples
    double computedVelX = 0;
    double computedVelY = 0;
    if (_dragSamples.length >= 2) {
      final first = _dragSamples.first;
      final last = _dragSamples.last;
      final dtMs = last.$1 - first.$1;
      if (dtMs > 0) {
        // px/sec
        computedVelX = (last.$2 - first.$2) / dtMs * 1000;
        computedVelY = (last.$3 - first.$3) / dtMs * 1000;
      }
    }
    _dragSamples.clear();

    _velocityX = computedVelX / 30; // Convert px/sec to px/tick (33ms)
    _velocityY = computedVelY / 30;

    if (_velocityX.abs() > 0.5) {
      _facingLeft = _velocityX < 0;
    }

    const friction = 0.95;
    const gravity = 0.5;
    final bottomY = _screenHeight - windowHeight;

    _inertiaTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      _velocityX *= friction;
      _velocityY *= friction;
      _velocityY += gravity;
      _x += _velocityX;
      _y += _velocityY;

      // Bounce off horizontal edges
      if (_x <= 0) {
        _x = 0;
        _velocityX = -_velocityX * 0.5;
      } else if (_x >= _screenWidth - windowWidth) {
        _x = _screenWidth - windowWidth;
        _velocityX = -_velocityX * 0.5;
      }

      // Bounce off top
      if (_y < 0) {
        _y = 0;
        _velocityY = -_velocityY * 0.5;
      }

      // Settle at bottom
      if (_y >= bottomY) {
        _y = bottomY;
        _velocityY = 0;
      }

      _updateWindowPosition();
      notifyListeners();

      // Stop when velocity is negligible and at bottom
      if (_velocityX.abs() < 0.1 &&
          _velocityY.abs() < 0.1 &&
          (_y - bottomY).abs() < 1) {
        timer.cancel();
        _y = bottomY;
        _isPaused = false;
        // Resume bounce animation and autonomous wandering
        if (!_bounceTicker.isActive) _bounceTicker.start();
        _moveTimer = Timer.periodic(
          const Duration(milliseconds: 33),
          (_) => _tick(),
        );
        _scheduleReverse();
        notifyListeners();
      }
    });
  }

  // --- Collision detection ---

  /// Write this mascot's position to a signal file for siblings to read.
  void _broadcastPosition() {
    final dir = signalDir;
    if (dir == null || _writingPosition) return;
    _writingPosition = true;
    File('$dir/mascot_position')
        .writeAsString('{"x":$_x,"y":$_y,"w":$windowWidth,"h":$windowHeight}')
        .then((_) => _writingPosition = false)
        .catchError((_) { _writingPosition = false; return File(''); });
  }

  /// Scan sibling signal directories for position files and resolve collisions.
  void _checkCollisions() {
    final dir = signalDir;
    if (dir == null) return;
    final parentDir = Directory(dir).parent;
    try {
      for (final entity in parentDir.listSync()) {
        if (entity is! Directory) continue;
        if (entity.path == dir) continue;
        final posFile = File('${entity.path}/mascot_position');
        if (!posFile.existsSync()) continue;
        posFile.readAsString().then((content) {
          try {
            final data = jsonDecode(content) as Map<String, dynamic>;
            resolveCollision(
              (data['x'] as num).toDouble(),
              (data['y'] as num).toDouble(),
              (data['w'] as num?)?.toDouble() ?? 150,
              (data['h'] as num?)?.toDouble() ?? 350,
            );
          } catch (_) {}
        }).catchError((_) {});
      }
    } catch (_) {}
  }

  /// Resolve collision with another mascot window (AABB).
  bool resolveCollision(
    double otherX,
    double otherY,
    double otherW,
    double otherH,
  ) {
    final myRight = _x + windowWidth;
    final myBottom = _y + windowHeight;
    final otherRight = otherX + otherW;
    final otherBottom = otherY + otherH;

    if (_x < otherRight &&
        myRight > otherX &&
        _y < otherBottom &&
        myBottom > otherY) {
      final overlapLeft = myRight - otherX;
      final overlapRight = otherRight - _x;

      if (overlapLeft < overlapRight) {
        _x = otherX - windowWidth;
        _facingLeft = true;
      } else {
        _x = otherRight;
        _facingLeft = false;
      }

      _x = _x.clamp(0.0, _screenWidth - windowWidth);
      _updateWindowPosition();
      notifyListeners();

      // Fire collision callback with cooldown
      final now = DateTime.now();
      if (_lastCollisionTime == null ||
          now.difference(_lastCollisionTime!) > _collisionCooldown) {
        _lastCollisionTime = now;
        onCollision?.call();
      }

      return true;
    }
    return false;
  }

  // --- Arm/item switching ---

  void _scheduleArmSwitch() {
    _armTimer?.cancel();
    // 15 to 45 seconds
    final delayMs = 15000 + _rng.nextInt(30001);
    _armTimer = Timer(Duration(milliseconds: delayMs), () {
      final states = ['empty', 'broom', 'luggage'];
      _armState = states[_rng.nextInt(states.length)];
      notifyListeners();
      _scheduleArmSwitch();
    });
  }

  @override
  void dispose() {
    _dropTimer?.cancel();
    _moveTimer?.cancel();
    _reverseTimer?.cancel();
    _pauseTimer?.cancel();
    _decelerationTimer?.cancel();
    _inertiaTimer?.cancel();
    _sparkleOnTimer?.cancel();
    _sparkleOffTimer?.cancel();
    _armTimer?.cancel();
    _bounceTicker.dispose();
    // Clean up position file
    if (signalDir != null) {
      try {
        final f = File('$signalDir/mascot_position');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }
}
