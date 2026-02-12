import 'dart:io';

import 'toml_parser.dart';

/// Configuration values for windows and wander behavior.
///
/// Loaded from `config/window.toml` if available, otherwise uses hardcoded
/// defaults. All fields have sensible defaults so the TOML file is optional.
class WindowConfig {
  // --- Main window ---
  final double mainWidth;
  final double mainHeight;

  // --- Child window ---
  final double childWidth;
  final double childHeight;
  final int maxChildren;

  // --- Wander window ---
  final double wanderWidth;
  final double wanderHeight;

  // --- Wander physics ---
  final double gravity;
  final double bounceDamping;
  final double friction;
  final double bottomMargin;
  final double inertiaFriction;
  final double inertiaGravity;

  // --- Wander animation ---
  final int bouncePeriodMs;
  final double bounceHeight;
  final double squishAmount;

  // --- Wander behavior ---
  final double speedMin;
  final double speedMax;
  final int reverseDelayMinMs;
  final int reverseDelayMaxMs;
  final int sparkleDelayMinMs;
  final int sparkleDelayMaxMs;
  final int sparkleDurationMs;
  final int armDelayMinMs;
  final int armDelayMaxMs;

  // --- Wander collision ---
  final int collisionCheckInterval;
  final int collisionCooldownSeconds;
  final double broadcastThreshold;

  // --- Swarm ---
  final int swarmThreshold;
  final int lod0TimeoutMs;
  final int signalPollMs;
  final double clickThroughInterval;

  const WindowConfig({
    this.mainWidth = 424.0,
    this.mainHeight = 528.0,
    this.childWidth = 264.0,
    this.childHeight = 528.0,
    this.maxChildren = 2,
    this.wanderWidth = 152.0,
    this.wanderHeight = 280.0,
    this.gravity = 0.8,
    this.bounceDamping = 0.4,
    this.friction = 0.98,
    this.bottomMargin = 50.0,
    this.inertiaFriction = 0.95,
    this.inertiaGravity = 0.5,
    this.bouncePeriodMs = 600,
    this.bounceHeight = 6.0,
    this.squishAmount = 0.03,
    this.speedMin = 0.4,
    this.speedMax = 1.2,
    this.reverseDelayMinMs = 5000,
    this.reverseDelayMaxMs = 15000,
    this.sparkleDelayMinMs = 8000,
    this.sparkleDelayMaxMs = 20000,
    this.sparkleDurationMs = 3000,
    this.armDelayMinMs = 15000,
    this.armDelayMaxMs = 45000,
    this.collisionCheckInterval = 18,
    this.collisionCooldownSeconds = 5,
    this.broadcastThreshold = 10.0,
    this.swarmThreshold = 5,
    this.lod0TimeoutMs = 6000,
    this.signalPollMs = 200,
    this.clickThroughInterval = 0.05,
  });

  /// Load from a TOML file, falling back to defaults for missing values.
  factory WindowConfig.fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return const WindowConfig();
    final toml = TomlParser.parse(file.readAsStringSync());
    return WindowConfig._fromToml(toml);
  }

  /// Load from a TOML string (for testing).
  factory WindowConfig.fromTomlString(String source) {
    final toml = TomlParser.parse(source);
    return WindowConfig._fromToml(toml);
  }

  /// Try to auto-detect the config file from standard locations.
  factory WindowConfig.autoDetect() {
    // Try relative to executable (release builds)
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final releaseConfig = '$exeDir/data/config/window.toml';
    if (File(releaseConfig).existsSync()) {
      return WindowConfig.fromFile(releaseConfig);
    }

    // Try walking up from exe dir (debug builds)
    var dir = Directory(exeDir);
    for (var i = 0; i < 10; i++) {
      dir = dir.parent;
      final candidate = '${dir.path}/config/window.toml';
      if (File(candidate).existsSync()) {
        return WindowConfig.fromFile(candidate);
      }
    }

    // Try CWD (flutter run)
    const cwdConfig = 'config/window.toml';
    if (File(cwdConfig).existsSync()) {
      return WindowConfig.fromFile(cwdConfig);
    }

    return const WindowConfig();
  }

  static WindowConfig _fromToml(Map<String, dynamic> toml) {
    final main = toml['main_window'] as Map<String, dynamic>? ?? {};
    final child = toml['child_window'] as Map<String, dynamic>? ?? {};
    final wander = toml['wander_window'] as Map<String, dynamic>? ?? {};
    final physics = _nested(toml, 'wander', 'physics');
    final animation = _nested(toml, 'wander', 'animation');
    final behavior = _nested(toml, 'wander', 'behavior');
    final collision = _nested(toml, 'wander', 'collision');
    final swarm = toml['swarm'] as Map<String, dynamic>? ?? {};

    return WindowConfig(
      mainWidth: _d(main['width']) ?? 424.0,
      mainHeight: _d(main['height']) ?? 528.0,
      childWidth: _d(child['width']) ?? 264.0,
      childHeight: _d(child['height']) ?? 528.0,
      maxChildren: _i(child['max_children']) ?? 2,
      wanderWidth: _d(wander['width']) ?? 152.0,
      wanderHeight: _d(wander['height']) ?? 280.0,
      gravity: _d(physics['gravity']) ?? 0.8,
      bounceDamping: _d(physics['bounce_damping']) ?? 0.4,
      friction: _d(physics['friction']) ?? 0.98,
      bottomMargin: _d(physics['bottom_margin']) ?? 50.0,
      inertiaFriction: _d(physics['inertia_friction']) ?? 0.95,
      inertiaGravity: _d(physics['inertia_gravity']) ?? 0.5,
      bouncePeriodMs: _i(animation['bounce_period_ms']) ?? 600,
      bounceHeight: _d(animation['bounce_height']) ?? 6.0,
      squishAmount: _d(animation['squish_amount']) ?? 0.03,
      speedMin: _d(behavior['speed_min']) ?? 0.4,
      speedMax: _d(behavior['speed_max']) ?? 1.2,
      reverseDelayMinMs: _i(behavior['reverse_delay_min_ms']) ?? 5000,
      reverseDelayMaxMs: _i(behavior['reverse_delay_max_ms']) ?? 15000,
      sparkleDelayMinMs: _i(behavior['sparkle_delay_min_ms']) ?? 8000,
      sparkleDelayMaxMs: _i(behavior['sparkle_delay_max_ms']) ?? 20000,
      sparkleDurationMs: _i(behavior['sparkle_duration_ms']) ?? 3000,
      armDelayMinMs: _i(behavior['arm_delay_min_ms']) ?? 15000,
      armDelayMaxMs: _i(behavior['arm_delay_max_ms']) ?? 45000,
      collisionCheckInterval: _i(collision['check_interval']) ?? 18,
      collisionCooldownSeconds: _i(collision['cooldown_seconds']) ?? 5,
      broadcastThreshold: _d(collision['broadcast_threshold']) ?? 10.0,
      swarmThreshold: _i(swarm['swarm_threshold']) ?? 5,
      lod0TimeoutMs: _i(swarm['lod0_timeout_ms']) ?? 6000,
      signalPollMs: _i(swarm['signal_poll_ms']) ?? 200,
      clickThroughInterval: _d(swarm['click_through_interval']) ?? 0.05,
    );
  }

  static Map<String, dynamic> _nested(
      Map<String, dynamic> toml, String section, String subsection) {
    final s = toml[section] as Map<String, dynamic>? ?? {};
    return s[subsection] as Map<String, dynamic>? ?? {};
  }

  static double? _d(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _i(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
