import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'mascot_entity.dart';
import 'sprite_cache.dart';
import 'swarm_simulation.dart';

/// CustomPainter that batch-draws all sprite-mode (LOD1) entities.
///
/// The active entity (LOD0) is excluded from sprite rendering and drawn
/// separately as a full PuppetWidget overlay.
class SwarmPainter extends CustomPainter {
  final SwarmSimulation simulation;
  final SpriteCache sprites;
  final int? activeEntityIndex;

  SwarmPainter({
    required this.simulation,
    required this.sprites,
    this.activeEntityIndex,
  }) : super(repaint: simulation);

  @override
  void paint(Canvas canvas, Size size) {
    if (!sprites.isReady) return;

    // Paint with medium filtering for downscaled 2x sprites
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final dstSize = ui.Size(sprites.spriteWidth, sprites.spriteHeight);

    for (var i = 0; i < simulation.entities.length; i++) {
      // Always draw sprites, even for the active (LOD0) entity.
      // The LOD0 MascotWidget overlays on top once loaded, preventing
      // a flash where the entity disappears during async model loading.
      final e = simulation.entities[i];
      if (e.dismissed) continue;

      final sprite = sprites.getFrame(
        e.facingLeft, e.isSpeaking, e.emotion,
        armState: e.armState,
      );
      if (sprite == null) continue;

      final (sx, sy) = e.squishScale;

      canvas.save();
      canvas.translate(e.x, e.y + e.bounceOffset);

      // Apply squish from bottom center
      if (sx != 1.0 || sy != 1.0) {
        canvas.translate(dstSize.width / 2, dstSize.height);
        canvas.scale(sx, sy);
        canvas.translate(-dstSize.width / 2, -dstSize.height);
      }

      // Draw 2x sprite scaled down to logical size
      final src = Rect.fromLTWH(
        0, 0,
        sprite.width.toDouble(), sprite.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, dstSize.width, dstSize.height);
      canvas.drawImageRect(sprite, src, dst, paint);
      canvas.restore();
    }
  }

  void _drawBubble(Canvas canvas, MascotEntity e) {
    final bubbleX = e.x + sprites.spriteWidth / 2;
    final bubbleY = e.y + e.bounceOffset + sprites.spriteHeight / 2 - 10;

    // Measure text
    final textSpan = TextSpan(
      text: e.message,
      style: const TextStyle(
        fontSize: 9,
        color: Colors.black87,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: sprites.spriteWidth - 12);

    final bubbleW = textPainter.width + 12;
    final bubbleH = textPainter.height + 6;
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bubbleX - bubbleW / 2,
        bubbleY - bubbleH - 6,
        bubbleW,
        bubbleH,
      ),
      const Radius.circular(8),
    );

    // Shadow
    canvas.drawRRect(
      bubbleRect.shift(const Offset(1, 2)),
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Background
    canvas.drawRRect(
      bubbleRect,
      Paint()..color = Colors.white,
    );

    // Tail
    final tailPath = ui.Path()
      ..moveTo(bubbleX - 5, bubbleY - 6)
      ..lineTo(bubbleX, bubbleY)
      ..lineTo(bubbleX + 5, bubbleY - 6)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = Colors.white);

    // Text
    textPainter.paint(canvas, Offset(bubbleX - bubbleW / 2 + 6, bubbleY - bubbleH - 3));
  }

  @override
  bool shouldRepaint(SwarmPainter oldDelegate) {
    return oldDelegate.activeEntityIndex != activeEntityIndex;
  }
}

/// Draws speech bubbles on top of everything (including LOD0 widget).
class BubblePainter extends CustomPainter {
  final SwarmSimulation simulation;
  final double spriteWidth;
  final double spriteHeight;

  BubblePainter({
    required this.simulation,
    required this.spriteWidth,
    required this.spriteHeight,
  }) : super(repaint: simulation);

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in simulation.entities) {
      if (e.dismissed) continue;
      if (e.isSpeaking && e.message.isNotEmpty) {
        _drawBubble(canvas, e);
      }
    }
  }

  void _drawBubble(Canvas canvas, MascotEntity e) {
    final bubbleX = e.x + spriteWidth / 2;
    final bubbleY = e.y + e.bounceOffset + spriteHeight / 4 - 10;

    // Measure text
    final textSpan = TextSpan(
      text: e.message,
      style: const TextStyle(
        fontSize: 9,
        color: Colors.black87,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: spriteWidth - 12);

    final bubbleW = textPainter.width + 12;
    final bubbleH = textPainter.height + 6;
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bubbleX - bubbleW / 2,
        bubbleY - bubbleH - 6,
        bubbleW,
        bubbleH,
      ),
      const Radius.circular(8),
    );

    // Shadow
    canvas.drawRRect(
      bubbleRect.shift(const Offset(1, 2)),
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Background
    canvas.drawRRect(
      bubbleRect,
      Paint()..color = Colors.white,
    );

    // Tail
    final tailPath = ui.Path()
      ..moveTo(bubbleX - 5, bubbleY - 6)
      ..lineTo(bubbleX, bubbleY)
      ..lineTo(bubbleX + 5, bubbleY - 6)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = Colors.white);

    // Text
    textPainter.paint(canvas, Offset(bubbleX - bubbleW / 2 + 6, bubbleY - bubbleH - 3));
  }

  @override
  bool shouldRepaint(BubblePainter oldDelegate) => false;
}
