import 'dart:math';

/// Lightweight data class representing a single mascot in the swarm.
///
/// No ChangeNotifier, no timers — all state is driven by [SwarmSimulation].
class MascotEntity {
  // --- Position ---
  double x;
  double y;
  double speed;
  double speedMultiplier;
  bool facingLeft;
  bool isPaused;
  bool isDragging;

  // --- Bounce ---
  double bouncePhase;

  // --- Visual state ---
  String armState; // 'empty' | 'broom' | 'luggage'
  bool sparklesActive;
  String? emotion;
  bool isSpeaking;
  String message;

  // --- Signal ---
  final String signalDir;

  // --- Countdown timers (in ticks) ---
  int reverseCountdown;
  int sparkleCountdown;
  int sparkleOffCountdown;
  int armCountdown;

  // --- Drop animation ---
  double dropVelX;
  double dropVelY;
  bool isDropping;
  int bounceCount;

  // --- Drag inertia ---
  double velocityX;
  double velocityY;
  bool isInertia;
  final List<(int, double, double)> dragSamples = [];

  // --- Dismiss ---
  bool dismissed;

  MascotEntity({
    required this.x,
    required this.y,
    required this.speed,
    required this.signalDir,
    this.speedMultiplier = 1.0,
    this.facingLeft = false,
    this.isPaused = false,
    this.isDragging = false,
    this.bouncePhase = 0,
    this.armState = 'luggage',
    this.sparklesActive = false,
    this.emotion,
    this.isSpeaking = false,
    this.message = '',
    this.reverseCountdown = 0,
    this.sparkleCountdown = 0,
    this.sparkleOffCountdown = 0,
    this.armCountdown = 0,
    this.dropVelX = 0,
    this.dropVelY = 0,
    this.isDropping = true,
    this.bounceCount = 0,
    this.velocityX = 0,
    this.velocityY = 0,
    this.isInertia = false,
    this.dismissed = false,
  });

  /// Bounce offset for rendering (negative = up).
  double get bounceOffset => isPaused || isDragging ? 0 : -6.0 * sin(bouncePhase);

  /// Squish scale factors for the "mochi" deformation effect.
  (double, double) get squishScale {
    if (isPaused || isDragging) return (1.0, 1.0);
    final t = sin(bouncePhase);
    const squishAmount = 0.03;
    return (1.0 - squishAmount * t, 1.0 + squishAmount * t);
  }

  /// Map of parameter overrides for PuppetController (sparkles, arm state).
  Map<String, double> get parameterOverrides {
    final m = <String, double>{};
    if (sparklesActive) m['Sparkles'] = 1.0;
    switch (armState) {
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
}
