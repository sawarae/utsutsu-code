/// Pachinko-inspired display effects for the desktop mascot.
///
/// Implements five effect types inspired by pachinko/pachislot machines:
/// - 保留変化 (Hold Change): Color aura upgrades through hierarchy
/// - フラッシュ (Flash): Dramatic white/gold flash overlay
/// - レインボー (Rainbow): Rotating rainbow shimmer aura
/// - 激アツ (Star Burst): Star/sparkle particles burst outward
/// - 振動 (Shake): Mascot shake/vibrate
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ── Effect Types ────────────────────────────────────────────

enum PachinkoEffectType {
  /// 保留変化 — Color aura upgrades: blue → green → red → gold.
  holdChange,

  /// フラッシュ — Dramatic flash overlay.
  flash,

  /// レインボー — Rotating rainbow shimmer aura.
  rainbow,

  /// 激アツ — Star/sparkle particles burst outward.
  starBurst,

  /// 振動 — Shake the mascot.
  shake,
}

// ── Active Effect State ─────────────────────────────────────

class ActiveEffect {
  final PachinkoEffectType type;
  final Color color;
  final double duration;
  final double intensity;
  double elapsed;
  bool completed;

  ActiveEffect({
    required this.type,
    this.color = const Color(0xFFFFFFFF),
    required this.duration,
    this.intensity = 1.0,
    this.elapsed = 0.0,
    this.completed = false,
  });

  /// Progress from 0.0 (start) to 1.0 (end).
  double get progress => (elapsed / duration).clamp(0.0, 1.0);
}

// ── Particle ────────────────────────────────────────────────

class Particle {
  double x, y;
  double vx, vy;
  double life;
  final double maxLife;
  final Color color;
  final double size;
  /// 0 = circle, 1 = 4-pointed star, 2 = diamond.
  final int shape;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.maxLife,
    required this.color,
    required this.size,
    this.shape = 0,
  }) : life = maxLife;

  bool get isDead => life <= 0;
  double get alpha => (life / maxLife).clamp(0.0, 1.0);

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 120.0 * dt; // gravity
    life -= dt;
  }
}

// ── Effect Controller ───────────────────────────────────────

/// Manages active pachinko display effects.
///
/// Call [tick] every frame with the elapsed delta time. Effects are added via
/// trigger methods and automatically removed when complete.
class PachinkoEffectController extends ChangeNotifier {
  final math.Random _rng;
  final List<ActiveEffect> _effects = [];
  final List<Particle> _particles = [];

  Offset _shakeOffset = Offset.zero;

  /// Current shake offset to apply as Transform.translate.
  Offset get shakeOffset => _shakeOffset;

  /// True when any effect or particle is currently active.
  bool get hasActiveEffects => _effects.isNotEmpty || _particles.isNotEmpty;

  /// Active effects (read-only view).
  List<ActiveEffect> get effects => List.unmodifiable(_effects);

  /// Active particles (read-only view).
  List<Particle> get particles => List.unmodifiable(_particles);

  PachinkoEffectController({int? seed}) : _rng = math.Random(seed);

  /// Trigger a dramatic flash overlay.
  void flash({
    Color color = const Color(0xFFFFFFFF),
    double duration = 0.4,
  }) {
    _effects.add(ActiveEffect(
      type: PachinkoEffectType.flash,
      color: color,
      duration: duration,
    ));
    notifyListeners();
  }

  /// Trigger a hold change (保留変化) color upgrade sequence.
  void holdChange({double duration = 2.0}) {
    _effects.add(ActiveEffect(
      type: PachinkoEffectType.holdChange,
      duration: duration,
    ));
    notifyListeners();
  }

  /// Trigger a rainbow aura shimmer.
  void rainbow({double duration = 3.0}) {
    _effects.add(ActiveEffect(
      type: PachinkoEffectType.rainbow,
      duration: duration,
    ));
    notifyListeners();
  }

  /// Trigger a star burst particle effect.
  void starBurst({Color? color, int count = 12}) {
    final c = color ?? _randomBrightColor();
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi + _rng.nextDouble() * 0.3;
      final speed = 80.0 + _rng.nextDouble() * 120.0;
      _particles.add(Particle(
        x: 0,
        y: 0,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 60.0,
        maxLife: 0.8 + _rng.nextDouble() * 0.6,
        color: c,
        size: 3.0 + _rng.nextDouble() * 4.0,
        shape: _rng.nextInt(3),
      ));
    }
    notifyListeners();
  }

  /// Trigger a shake effect.
  void shake({double duration = 0.5, double intensity = 4.0}) {
    _effects.add(ActiveEffect(
      type: PachinkoEffectType.shake,
      duration: duration,
      intensity: intensity,
    ));
    notifyListeners();
  }

  /// Trigger effects appropriate for the given emotion.
  void triggerForEmotion(String emotion) {
    switch (emotion) {
      case 'Joy':
        flash(color: const Color(0xFFFFD54F), duration: 0.3);
        starBurst(color: const Color(0xFFFFD54F), count: 16);
        holdChange(duration: 1.5);
      case 'Singing':
        rainbow(duration: 4.0);
        starBurst(color: const Color(0xFFFF8F00), count: 20);
      case 'Blush':
        holdChange(duration: 1.0);
        _spawnHearts(8);
      case 'Trouble':
        shake(duration: 0.6, intensity: 5.0);
        flash(color: const Color(0xFF7E57C2), duration: 0.2);
      case 'Gentle':
        holdChange(duration: 1.5);
    }
  }

  void _spawnHearts(int count) {
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + (_rng.nextDouble() - 0.5) * math.pi;
      final speed = 40.0 + _rng.nextDouble() * 80.0;
      _particles.add(Particle(
        x: (_rng.nextDouble() - 0.5) * 40,
        y: (_rng.nextDouble() - 0.5) * 40,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        maxLife: 1.0 + _rng.nextDouble() * 0.5,
        color: Color.lerp(
          const Color(0xFFE91E63),
          const Color(0xFFF48FB1),
          _rng.nextDouble(),
        )!,
        size: 4.0 + _rng.nextDouble() * 3.0,
        shape: 2,
      ));
    }
    notifyListeners();
  }

  Color _randomBrightColor() {
    const colors = [
      Color(0xFFFFD54F),
      Color(0xFFEF5350),
      Color(0xFF42A5F5),
      Color(0xFF66BB6A),
      Color(0xFFFF8F00),
      Color(0xFFAB47BC),
    ];
    return colors[_rng.nextInt(colors.length)];
  }

  /// Advance all effects by [dt] seconds. Call every frame.
  void tick(double dt) {
    if (!hasActiveEffects) return;

    _shakeOffset = Offset.zero;
    for (final effect in _effects) {
      effect.elapsed += dt;
      if (effect.elapsed >= effect.duration) {
        effect.completed = true;
      }
      if (effect.type == PachinkoEffectType.shake && !effect.completed) {
        final decay = 1.0 - effect.progress;
        final mag = effect.intensity * decay;
        _shakeOffset += Offset(
          (_rng.nextDouble() - 0.5) * 2 * mag,
          (_rng.nextDouble() - 0.5) * 2 * mag,
        );
      }
    }
    _effects.removeWhere((e) => e.completed);

    for (final p in _particles) {
      p.update(dt);
    }
    _particles.removeWhere((p) => p.isDead);

    notifyListeners();
  }

  /// Remove all active effects immediately.
  void clear() {
    _effects.clear();
    _particles.clear();
    _shakeOffset = Offset.zero;
    notifyListeners();
  }
}

// ── Overlay Widget ──────────────────────────────────────────

/// Renders pachinko effects on top of its child widget.
///
/// Wraps [child] in a Stack. When effects are active, a CustomPaint overlay
/// draws flashes, auras, and particles, while shake effects apply a
/// Transform.translate to the child.
class PachinkoEffectOverlay extends StatefulWidget {
  final Widget child;
  final PachinkoEffectController controller;

  const PachinkoEffectOverlay({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<PachinkoEffectOverlay> createState() => PachinkoEffectOverlayState();
}

class PachinkoEffectOverlayState extends State<PachinkoEffectOverlay>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onEffectChanged);
  }

  @override
  void didUpdateWidget(PachinkoEffectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onEffectChanged);
      widget.controller.addListener(_onEffectChanged);
    }
  }

  void _onEffectChanged() {
    if (widget.controller.hasActiveEffects && _ticker == null) {
      _lastElapsed = Duration.zero;
      _ticker = createTicker(_onTick)..start();
    }
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 0.016
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    widget.controller.tick(dt.clamp(0.0, 0.1));

    if (!widget.controller.hasActiveEffects) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    widget.controller.removeListener(_onEffectChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shake = widget.controller.shakeOffset;
    return Stack(
      children: [
        Transform.translate(
          offset: shake,
          child: widget.child,
        ),
        if (widget.controller.hasActiveEffects)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PachinkoEffectPainter(
                  effects: widget.controller.effects,
                  particles: widget.controller.particles,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Painter ─────────────────────────────────────────────────

/// Custom painter that renders all active pachinko effects and particles.
class PachinkoEffectPainter extends CustomPainter {
  final List<ActiveEffect> effects;
  final List<Particle> particles;

  PachinkoEffectPainter({
    required this.effects,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final effect in effects) {
      switch (effect.type) {
        case PachinkoEffectType.flash:
          _paintFlash(canvas, size, effect);
        case PachinkoEffectType.holdChange:
          _paintHoldChange(canvas, size, effect);
        case PachinkoEffectType.rainbow:
          _paintRainbow(canvas, size, effect);
        case PachinkoEffectType.starBurst:
        case PachinkoEffectType.shake:
          break; // handled elsewhere
      }
    }

    for (final p in particles) {
      _paintParticle(canvas, center, p);
    }
  }

  void _paintFlash(Canvas canvas, Size size, ActiveEffect effect) {
    final t = effect.progress;
    // Quick in (20%), slow out (80%)
    final alpha = t < 0.2 ? (t / 0.2) : (1.0 - (t - 0.2) / 0.8);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = effect.color.withOpacity(alpha.clamp(0.0, 1.0) * 0.6),
    );
  }

  void _paintHoldChange(Canvas canvas, Size size, ActiveEffect effect) {
    // 保留変化: blue → green → red → gold with pulsing glow border
    const colors = [
      Color(0xFF42A5F5), // Blue
      Color(0xFF66BB6A), // Green
      Color(0xFFEF5350), // Red
      Color(0xFFFFD54F), // Gold
    ];

    final t = effect.progress;
    final segment = t * colors.length;
    final idx = segment.floor().clamp(0, colors.length - 1);
    final nextIdx = (idx + 1).clamp(0, colors.length - 1);
    final lerp = (segment - idx).clamp(0.0, 1.0);
    final color = Color.lerp(colors[idx], colors[nextIdx], lerp)!;

    // Pulsing alpha
    final pulse = (0.3 + 0.3 * math.sin(t * 12 * math.pi)).clamp(0.0, 1.0);

    // Glow border (ring, not filled)
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final outer = rect;
    final inner = rect.deflate(15);
    final path = Path()
      ..addRect(outer)
      ..addRect(inner);
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
  }

  void _paintRainbow(Canvas canvas, Size size, ActiveEffect effect) {
    final t = effect.progress;
    final center = Offset(size.width / 2, size.height / 2);
    final rotation = t * 4 * math.pi;

    // Fade in/out
    final alpha = t < 0.1
        ? t / 0.1
        : (t > 0.8 ? (1.0 - t) / 0.2 : 1.0);

    final paint = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        const [
          Color(0xFFFF0000),
          Color(0xFFFF8800),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF0088FF),
          Color(0xFF8800FF),
          Color(0xFFFF0000),
        ],
        null,
        TileMode.clamp,
        rotation,
        rotation + 2 * math.pi,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    // Apply alpha via saveLayer
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0)),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: size.width * 0.9,
        height: size.height * 0.9,
      ),
      paint,
    );
    canvas.restore();
  }

  void _paintParticle(Canvas canvas, Offset center, Particle p) {
    final pos = Offset(center.dx + p.x, center.dy + p.y);
    final paint = Paint()..color = p.color.withOpacity(p.alpha);
    final s = p.size * p.alpha;

    switch (p.shape) {
      case 0:
        canvas.drawCircle(pos, s, paint);
      case 1:
        _drawStar(canvas, pos, s, paint);
      case 2:
        _drawDiamond(canvas, pos, s, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset c, double size, Paint paint) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final ox = c.dx + math.cos(angle) * size;
      final oy = c.dy + math.sin(angle) * size;
      final ia = angle + math.pi / 4;
      final ix = c.dx + math.cos(ia) * size * 0.4;
      final iy = c.dy + math.sin(ia) * size * 0.4;
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawDiamond(Canvas canvas, Offset c, double size, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - size)
      ..lineTo(c.dx + size * 0.6, c.dy)
      ..lineTo(c.dx, c.dy + size)
      ..lineTo(c.dx - size * 0.6, c.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PachinkoEffectPainter old) => true;
}
