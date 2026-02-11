import 'dart:async';
import 'dart:io' show Platform;
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

  // --- Movement state ---
  double _x = 0;
  double _y = 0;
  double _screenWidth = 1920;
  bool _facingLeft = false;
  bool _isPaused = false;
  double _speed; // px per tick (~30fps)
  Timer? _moveTimer;

  // --- Reverse scheduling ---
  Timer? _reverseTimer;
  Timer? _pauseTimer;

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

  // --- Public getters ---
  bool get facingLeft => _facingLeft;
  double get bounceOffset => _isPaused ? 0 : -_bounceHeight * sin(_bouncePhase);
  bool get sparklesActive => _sparklesActive;
  String get armState => _armState;
  bool get isPaused => _isPaused;

  /// Squish scale factors for the "mochi" deformation effect.
  ///
  /// At the top of the bounce, the character is slightly taller and narrower.
  /// At the bottom, it's shorter and wider.
  /// Returns (scaleX, scaleY).
  (double, double) get squishScale {
    if (_isPaused) return (1.0, 1.0);
    final t = sin(_bouncePhase);
    // scaleX: wider at bottom (t=-1 → 1.07), narrower at top (t=1 → 0.93)
    final sx = 1.0 - 0.07 * t;
    // scaleY: taller at top (t=1 → 1.07), shorter at bottom (t=-1 → 0.93)
    final sy = 1.0 + 0.07 * t;
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
    this.windowHeight = 300,
  }) : _rng = Random(seed),
       _speed = 0 {
    _speed = _randomSpeed();
    _bounceTicker = Ticker(_onBounceTick);
  }

  /// Initialise and start wandering. Call once after construction.
  Future<void> start() async {
    // Determine screen width
    final display = await screenRetriever.getPrimaryDisplay();
    _screenWidth = display.size.width;

    // Start at a random X within the screen
    _x = _rng.nextDouble() * (_screenWidth - windowWidth);
    _facingLeft = _rng.nextBool();

    // Position the window at the bottom of the screen
    _y = display.size.height - windowHeight;
    await windowManager.setPosition(Offset(_x, _y));

    // Start movement timer (~30fps)
    _moveTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _tick(),
    );

    // Start bounce animation
    _bounceTicker.start();

    // Schedule first direction reversal
    _scheduleReverse();

    // Schedule first sparkle
    _scheduleSparkle();

    // Schedule first arm switch
    _scheduleArmSwitch();
  }

  double _randomSpeed() {
    // 0.4 to 1.2 px per tick (33ms) → 12 to 36 px/sec
    return 0.4 + _rng.nextDouble() * 0.8;
  }

  void _tick() {
    if (_isPaused) return;

    // Move
    final dx = _facingLeft ? -_speed : _speed;
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
    _isPaused = true;
    _reverseTimer?.cancel();
    notifyListeners();

    // Pause 0.5 to 2 seconds
    final pauseMs = 500 + _rng.nextInt(1501);
    _pauseTimer = Timer(Duration(milliseconds: pauseMs), () {
      _facingLeft = goLeft;
      _speed = _randomSpeed();
      _isPaused = false;
      notifyListeners();
      _scheduleReverse();
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
    _moveTimer?.cancel();
    _reverseTimer?.cancel();
    _pauseTimer?.cancel();
    _sparkleOnTimer?.cancel();
    _sparkleOffTimer?.cancel();
    _armTimer?.cancel();
    _bounceTicker.dispose();
    super.dispose();
  }
}
