import 'dart:math' as math;

/// Exterior or partition boundary side on an axis-aligned architectural room rectangle.
enum ArchWallSide {
  north,
  south,
  west,
  east,
}

/// Programmatic room requirement fed into [ArchFloorplanSolver].
final class ArchRoomSpec {
  final String id;
  final String role;
  final double targetWeight;
  final double minExtent;
  final double maxAspectRatio;
  final bool preferredExteriorWindow;
  final bool connectsToExterior;
  final List<String> requiredAdjacencyIds;

  const ArchRoomSpec({
    required this.id,
    this.role = 'room',
    this.targetWeight = 1.0,
    this.minExtent = 2.5,
    this.maxAspectRatio = 2.6,
    this.preferredExteriorWindow = true,
    this.connectsToExterior = false,
    this.requiredAdjacencyIds = const [],
  });
}

/// Shared boundary segment between two adjacent axis-aligned room rectangles.
final class ArchSharedWall {
  final String roomAId;
  final String roomBId;
  final ArchWallSide sideOnA;
  final bool spansAlongX;
  final double overlapStart;
  final double overlapEnd;
  final double wallCoord;

  const ArchSharedWall({
    required this.roomAId,
    required this.roomBId,
    required this.sideOnA,
    required this.spansAlongX,
    required this.overlapStart,
    required this.overlapEnd,
    required this.wallCoord,
  });

  double get overlapLength => math.max(0.0, overlapEnd - overlapStart);
  double get midAlongWall => (overlapStart + overlapEnd) * 0.5;
  double get centerX => spansAlongX ? midAlongWall : wallCoord;
  double get centerY => spansAlongX ? wallCoord : midAlongWall;
}

/// Subdivided rectangular room parcel inside a generated floorplan.
final class ArchRoomRect {
  final String id;
  final String role;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool isCorridor;
  final Set<ArchWallSide> exteriorSides;

  const ArchRoomRect({
    required this.id,
    required this.role,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.isCorridor = false,
    this.exteriorSides = const {},
  });

  double get left => x;
  double get right => x + width;
  double get top => y;
  double get bottom => y + height;
  double get centerX => x + width * 0.5;
  double get centerY => y + height * 0.5;
  double get area => width * height;
  double get aspectRatio {
    final lo = math.min(width, height);
    final hi = math.max(width, height);
    return lo <= 1e-6 ? 999.0 : hi / lo;
  }

  /// Computes shared wall overlap segment with [other], or `null` if non-adjacent.
  ArchSharedWall? sharedWallWith(ArchRoomRect other, {double tolerance = 1e-3}) {
    if ((right - other.left).abs() <= tolerance || (left - other.right).abs() <= tolerance) {
      final isRightEdge = (right - other.left).abs() <= tolerance;
      final start = math.max(top, other.top);
      final end = math.min(bottom, other.bottom);
      if (end > start + tolerance) {
        return ArchSharedWall(
          roomAId: id,
          roomBId: other.id,
          sideOnA: isRightEdge ? ArchWallSide.east : ArchWallSide.west,
          spansAlongX: false,
          overlapStart: start,
          overlapEnd: end,
          wallCoord: isRightEdge ? right : left,
        );
      }
    }
    if ((bottom - other.top).abs() <= tolerance || (top - other.bottom).abs() <= tolerance) {
      final isBottomEdge = (bottom - other.top).abs() <= tolerance;
      final start = math.max(left, other.left);
      final end = math.min(right, other.right);
      if (end > start + tolerance) {
        return ArchSharedWall(
          roomAId: id,
          roomBId: other.id,
          sideOnA: isBottomEdge ? ArchWallSide.south : ArchWallSide.north,
          spansAlongX: true,
          overlapStart: start,
          overlapEnd: end,
          wallCoord: isBottomEdge ? bottom : top,
        );
      }
    }
    return null;
  }
}

/// Traversable doorway portal between two rooms or an exterior facade entrance.
final class ArchDoorway {
  final String id;
  final String roomAId;
  final String roomBId;
  final double centerX;
  final double centerY;
  final double width;
  final bool spansAlongX;
  final ArchWallSide wallSideOnA;
  final double swingClearance;
  final bool isExteriorEntrance;
  final bool isCorridorLink;

  const ArchDoorway({
    required this.id,
    required this.roomAId,
    required this.roomBId,
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.spansAlongX,
    required this.wallSideOnA,
    this.swingClearance = 0.9,
    this.isExteriorEntrance = false,
    this.isCorridorLink = false,
  });
}

/// Facade window opening placed on an exterior room perimeter wall.
final class ArchWindowPlacement {
  final String id;
  final String roomId;
  final ArchWallSide exteriorSide;
  final double centerX;
  final double centerY;
  final double width;

  const ArchWindowPlacement({
    required this.id,
    required this.roomId,
    required this.exteriorSide,
    required this.centerX,
    required this.centerY,
    required this.width,
  });
}
