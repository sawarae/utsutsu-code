import 'mascot_entity.dart';

/// Spatial hash grid for O(n) collision detection among mascot entities.
///
/// Each entity is inserted into a grid cell based on its position.
/// Collision resolution checks within each cell and adjacent cells.
class CollisionGrid {
  final double cellSize;
  final double screenWidth;
  final double screenHeight;
  final double entityWidth;
  final double entityHeight;
  final Map<int, List<MascotEntity>> _cells = {};

  CollisionGrid({
    required this.cellSize,
    required this.screenWidth,
    required this.screenHeight,
    required this.entityWidth,
    required this.entityHeight,
  });

  int _key(double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    return cx * 100000 + cy;
  }

  void clear() {
    _cells.clear();
  }

  void insert(MascotEntity e) {
    // Insert into all cells the entity overlaps
    final minCx = (e.x / cellSize).floor();
    final maxCx = ((e.x + entityWidth) / cellSize).floor();
    final minCy = (e.y / cellSize).floor();
    final maxCy = ((e.y + entityHeight) / cellSize).floor();
    for (var cx = minCx; cx <= maxCx; cx++) {
      for (var cy = minCy; cy <= maxCy; cy++) {
        final key = cx * 100000 + cy;
        _cells.putIfAbsent(key, () => []).add(e);
      }
    }
  }

  /// Resolve all collisions. Returns the number of collision pairs resolved.
  int resolveCollisions() {
    var count = 0;
    final processed = <int>{};

    for (final cell in _cells.values) {
      for (var i = 0; i < cell.length; i++) {
        for (var j = i + 1; j < cell.length; j++) {
          final a = cell[i];
          final b = cell[j];
          // Create unique pair key to avoid double-processing
          final pairKey = a.hashCode < b.hashCode
              ? a.hashCode * 1000003 + b.hashCode
              : b.hashCode * 1000003 + a.hashCode;
          if (processed.contains(pairKey)) continue;
          processed.add(pairKey);

          if (_resolveAABB(a, b)) count++;
        }
      }
    }
    return count;
  }

  bool _resolveAABB(MascotEntity a, MascotEntity b) {
    final aRight = a.x + entityWidth;
    final aBottom = a.y + entityHeight;
    final bRight = b.x + entityWidth;
    final bBottom = b.y + entityHeight;

    // AABB overlap test
    if (a.x >= bRight || aRight <= b.x || a.y >= bBottom || aBottom <= b.y) {
      return false;
    }

    // Push apart horizontally (same logic as current WanderController)
    final overlapLeft = aRight - b.x;
    final overlapRight = bRight - a.x;

    if (overlapLeft < overlapRight) {
      // Push a left, b right
      final halfOverlap = overlapLeft / 2;
      a.x -= halfOverlap;
      b.x += halfOverlap;
    } else {
      // Push a right, b left
      final halfOverlap = overlapRight / 2;
      a.x += halfOverlap;
      b.x -= halfOverlap;
    }

    // Clamp to screen bounds
    a.x = a.x.clamp(0.0, screenWidth - entityWidth);
    b.x = b.x.clamp(0.0, screenWidth - entityWidth);

    // Update facing directions based on relative position
    if (a.x < b.x) {
      a.facingLeft = true;
      b.facingLeft = false;
    } else {
      a.facingLeft = false;
      b.facingLeft = true;
    }

    return true;
  }
}
