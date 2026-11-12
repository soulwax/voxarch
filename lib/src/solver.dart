import 'dart:collection';
import 'dart:math' as math;

import 'spec.dart';

final class _ParcelAllocation {
  final double x;
  final double y;
  final double w;
  final double h;
  final ArchRoomSpec spec;
  final bool isCorridor;

  const _ParcelAllocation({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.spec,
    this.isCorridor = false,
  });
}

/// Deterministic seeded architectural BSP/squarified split-grammar.
final class ArchSplitGrammar {
  final double minRoomExtent;
  final double corridorWidth;
  final double jitterRatio;

  const ArchSplitGrammar({
    this.minRoomExtent = 2.4,
    this.corridorWidth = 1.8,
    this.jitterRatio = 0.14,
  });

  /// Subdivides `[boundsWidth x boundsDepth]` parcel among [specs].
  List<ArchRoomRect> subdivide(
    List<ArchRoomSpec> specs, {
    required double boundsWidth,
    required double boundsDepth,
    int seed = 1,
    bool carveCentralCorridor = false,
  }) {
    if (specs.isEmpty) {
      return [
        ArchRoomRect(
          id: 'main_hall',
          role: 'hall',
          x: 0.0,
          y: 0.0,
          width: boundsWidth,
          height: boundsDepth,
          exteriorSides: const {
            ArchWallSide.north,
            ArchWallSide.south,
            ArchWallSide.west,
            ArchWallSide.east,
          },
        ),
      ];
    }

    final ordered = _orderForAdjacency(specs);
    final rng = math.Random(seed);
    final raw = <_ParcelAllocation>[];

    if (carveCentralCorridor && ordered.length >= 3) {
      final horizontalCorridor = boundsWidth >= boundsDepth;
      final effCorridorW = math.min(
        corridorWidth,
        (horizontalCorridor ? boundsDepth : boundsWidth) * 0.25,
      );
      if (horizontalCorridor && boundsDepth >= effCorridorW + minRoomExtent * 1.5) {
        final northH = (boundsDepth - effCorridorW) * 0.5;
        final southY = northH + effCorridorW;
        final southH = boundsDepth - southY;
        final halfIdx = (ordered.length + 1) ~/ 2;
        _subdivideRecursive(
          ordered.sublist(0, halfIdx),
          0.0,
          0.0,
          boundsWidth,
          northH,
          rng,
          raw,
        );
        raw.add(
          _ParcelAllocation(
            x: 0.0,
            y: northH,
            w: boundsWidth,
            h: effCorridorW,
            spec: const ArchRoomSpec(
              id: 'corridor_spine',
              role: 'corridor',
              preferredExteriorWindow: false,
            ),
            isCorridor: true,
          ),
        );
        _subdivideRecursive(
          ordered.sublist(halfIdx),
          0.0,
          southY,
          boundsWidth,
          southH,
          rng,
          raw,
        );
      } else if (!horizontalCorridor && boundsWidth >= effCorridorW + minRoomExtent * 1.5) {
        final westW = (boundsWidth - effCorridorW) * 0.5;
        final eastX = westW + effCorridorW;
        final eastW = boundsWidth - eastX;
        final halfIdx = (ordered.length + 1) ~/ 2;
        _subdivideRecursive(
          ordered.sublist(0, halfIdx),
          0.0,
          0.0,
          westW,
          boundsDepth,
          rng,
          raw,
        );
        raw.add(
          _ParcelAllocation(
            x: westW,
            y: 0.0,
            w: effCorridorW,
            h: boundsDepth,
            spec: const ArchRoomSpec(
              id: 'corridor_spine',
              role: 'corridor',
              preferredExteriorWindow: false,
            ),
            isCorridor: true,
          ),
        );
        _subdivideRecursive(
          ordered.sublist(halfIdx),
          eastX,
          0.0,
          eastW,
          boundsDepth,
          rng,
          raw,
        );
      } else {
        _subdivideRecursive(ordered, 0.0, 0.0, boundsWidth, boundsDepth, rng, raw);
      }
    } else {
      _subdivideRecursive(ordered, 0.0, 0.0, boundsWidth, boundsDepth, rng, raw);
    }

    const eps = 1e-4;
    return [
      for (final p in raw)
        ArchRoomRect(
          id: p.spec.id,
          role: p.spec.role,
          x: p.x,
          y: p.y,
          width: p.w,
          height: p.h,
          isCorridor: p.isCorridor,
          exteriorSides: {
            if (p.y <= eps) ArchWallSide.north,
            if ((p.y + p.h - boundsDepth).abs() <= eps) ArchWallSide.south,
            if (p.x <= eps) ArchWallSide.west,
            if ((p.x + p.w - boundsWidth).abs() <= eps) ArchWallSide.east,
          },
        ),
    ];
  }

  /// Greedy ordering placing rooms with mutual adjacency constraints next to each other.
  List<ArchRoomSpec> _orderForAdjacency(List<ArchRoomSpec> specs) {
    final byId = {for (final s in specs) s.id: s};
    final placed = <String>{};
    final out = <ArchRoomSpec>[];

    // Prefer starting with any room marked connectsToExterior.
    final queue = Queue<ArchRoomSpec>();
    final starters = specs.where((s) => s.connectsToExterior).toList();
    if (starters.isNotEmpty) {
      queue.add(starters.first);
    } else {
      queue.add(specs.first);
    }

    void flushQueue() {
      while (queue.isNotEmpty) {
        final cur = queue.removeFirst();
        if (!placed.add(cur.id)) continue;
        out.add(cur);
        for (final adjId in cur.requiredAdjacencyIds) {
          final target = byId[adjId];
          if (target != null && !placed.contains(target.id)) {
            queue.add(target);
          }
        }
        for (final other in specs) {
          if (!placed.contains(other.id) && other.requiredAdjacencyIds.contains(cur.id)) {
            queue.add(other);
          }
        }
      }
    }

    flushQueue();
    for (final s in specs) {
      if (!placed.contains(s.id)) {
        queue.add(s);
        flushQueue();
      }
    }
    return out;
  }

  void _subdivideRecursive(
    List<ArchRoomSpec> group,
    double x,
    double y,
    double w,
    double h,
    math.Random rng,
    List<_ParcelAllocation> out,
  ) {
    if (group.isEmpty) return;
    if (group.length == 1) {
      out.add(_ParcelAllocation(x: x, y: y, w: w, h: h, spec: group.first));
      return;
    }

    var totalWeight = 0.0;
    for (final s in group) {
      totalWeight += math.max(0.1, s.targetWeight);
    }

    // Partition list into two contiguous slices close to balanced weight ratio
    var leftWeight = 0.0;
    var splitIdx = 1;
    var bestDiff = double.infinity;
    for (var i = 0; i < group.length - 1; i++) {
      leftWeight += math.max(0.1, group[i].targetWeight);
      final diff = (leftWeight - totalWeight * 0.5).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        splitIdx = i + 1;
      }
    }

    final firstHalf = group.sublist(0, splitIdx);
    final secondHalf = group.sublist(splitIdx);
    var firstWeight = 0.0;
    for (final s in firstHalf) {
      firstWeight += math.max(0.1, s.targetWeight);
    }

    final splitVertical = w >= h;
    final baseRatio = (firstWeight / math.max(1e-6, totalWeight)).clamp(0.18, 0.82);
    final jitter = (rng.nextDouble() * 2.0 - 1.0) * jitterRatio;
    var ratio = (baseRatio + jitter).clamp(0.2, 0.8);

    final axisLen = splitVertical ? w : h;
    final minFirst = math.min(axisLen * 0.45, firstHalf.length == 1 ? firstHalf.first.minExtent : minRoomExtent);
    final minSecond = math.min(axisLen * 0.45, secondHalf.length == 1 ? secondHalf.first.minExtent : minRoomExtent);
    final rawSplit = (axisLen * ratio).clamp(minFirst, math.max(minFirst, axisLen - minSecond)).toDouble();

    if (splitVertical) {
      _subdivideRecursive(firstHalf, x, y, rawSplit, h, rng, out);
      _subdivideRecursive(secondHalf, x + rawSplit, y, w - rawSplit, h, rng, out);
    } else {
      _subdivideRecursive(firstHalf, x, y, w, rawSplit, rng, out);
      _subdivideRecursive(secondHalf, x, y + rawSplit, w, h - rawSplit, rng, out);
    }
  }
}

/// Solved procedural architectural floorplan with room connectivity verification.
final class ArchFloorplanResult {
  final double boundsWidth;
  final double boundsDepth;
  final int seed;
  final List<ArchRoomRect> rooms;
  final List<ArchDoorway> doorways;
  final List<ArchWindowPlacement> windows;
  final Map<String, Set<String>> adjacencyGraph;
  final Set<String> disconnectedRoomIds;
  final List<(String, String)> unmetAdjacencies;

  const ArchFloorplanResult({
    required this.boundsWidth,
    required this.boundsDepth,
    required this.seed,
    required this.rooms,
    required this.doorways,
    required this.windows,
    required this.adjacencyGraph,
    required this.disconnectedRoomIds,
    required this.unmetAdjacencies,
  });

  bool get isFullyConnected => disconnectedRoomIds.isEmpty;

  double get totalArea => rooms.fold(0.0, (acc, r) => acc + r.area);

  ArchRoomRect? roomById(String id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Shortest room-to-room traversal sequence over doorway links using BFS.
  List<String> shortestRoomPath(String startId, String goalId) {
    if (startId == goalId) return [startId];
    if (!adjacencyGraph.containsKey(startId) || !adjacencyGraph.containsKey(goalId)) {
      return const [];
    }
    final queue = Queue<String>()..add(startId);
    final parent = <String, String?>{startId: null};
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      if (cur == goalId) {
        final path = <String>[];
        String? node = cur;
        while (node != null) {
          path.add(node);
          node = parent[node];
        }
        return path.reversed.toList();
      }
      for (final next in adjacencyGraph[cur] ?? const <String>{}) {
        if (!parent.containsKey(next)) {
          parent[next] = cur;
          queue.add(next);
        }
      }
    }
    return const [];
  }

  /// Renders a compact ASCII floorplan map for diagnostics & CLI inspection.
  String toAsciiPreview({int cols = 40, int rows = 20}) {
    final grid = List.generate(rows, (_) => List.filled(cols, ' '));
    for (var ry = 0; ry < rows; ry++) {
      final wy = (ry + 0.5) * boundsDepth / rows;
      for (var cx = 0; cx < cols; cx++) {
        final wx = (cx + 0.5) * boundsWidth / cols;
        String ch = '.';
        for (var i = 0; i < rooms.length; i++) {
          final r = rooms[i];
          if (wx >= r.left && wx <= r.right && wy >= r.top && wy <= r.bottom) {
            if (r.isCorridor) {
              ch = '#';
            } else {
              final tag = r.id.isNotEmpty ? r.id[0].toUpperCase() : '${i % 10}';
              ch = tag;
            }
            break;
          }
        }
        grid[ry][cx] = ch;
      }
    }
    return grid.map((line) => line.join()).join('\n');
  }
}

/// Complete floorplan generator solving split subdivision, doorway portals, connectivity & windows.
final class ArchFloorplanSolver {
  double boundsWidth;
  double boundsDepth;
  double minRoomExtent;
  double doorWidth;
  double corridorWidth;
  double windowWidth;
  double jitterRatio;
  bool carveCentralCorridor;

  ArchFloorplanSolver({
    this.boundsWidth = 20.0,
    this.boundsDepth = 14.0,
    this.minRoomExtent = 2.5,
    this.doorWidth = 1.1,
    this.corridorWidth = 1.8,
    this.windowWidth = 1.4,
    this.jitterRatio = 0.14,
    this.carveCentralCorridor = false,
  });

  ArchFloorplanResult solve(List<ArchRoomSpec> specs, {int seed = 1}) {
    final grammar = ArchSplitGrammar(
      minRoomExtent: minRoomExtent,
      corridorWidth: corridorWidth,
      jitterRatio: jitterRatio,
    );

    final rooms = grammar.subdivide(
      specs,
      boundsWidth: boundsWidth,
      boundsDepth: boundsDepth,
      seed: seed,
      carveCentralCorridor: carveCentralCorridor,
    );

    final roomMap = {for (final r in rooms) r.id: r};
    final specMap = {for (final s in specs) s.id: s};

    // Collect all shared wall segments between pairs
    final sharedWalls = <(String, String), ArchSharedWall>{};
    for (var i = 0; i < rooms.length; i++) {
      for (var j = i + 1; j < rooms.length; j++) {
        final w = rooms[i].sharedWallWith(rooms[j]);
        if (w != null) {
          sharedWalls[(rooms[i].id, rooms[j].id)] = w;
        }
      }
    }

    final doorways = <ArchDoorway>[];
    final adjacency = <String, Set<String>>{for (final r in rooms) r.id: <String>{}};
    final connectedEdges = <(String, String)>{};
    var doorSeq = 1;

    void addDoor(ArchSharedWall wall, {bool isCorridorLink = false}) {
      final a = wall.roomAId;
      final b = wall.roomBId;
      final pair = a.compareTo(b) < 0 ? (a, b) : (b, a);
      if (connectedEdges.contains(pair)) return;

      final effWidth = math.min(doorWidth, wall.overlapLength * 0.78);
      if (effWidth < 0.55) return;

      connectedEdges.add(pair);
      adjacency[a]!.add(b);
      adjacency[b]!.add(a);
      doorways.add(
        ArchDoorway(
          id: 'door_${doorSeq++}',
          roomAId: a,
          roomBId: b,
          centerX: wall.centerX,
          centerY: wall.centerY,
          width: effWidth,
          spansAlongX: wall.spansAlongX,
          wallSideOnA: wall.sideOnA,
          swingClearance: effWidth * 0.85,
          isCorridorLink: isCorridorLink ||
              (roomMap[a]?.isCorridor ?? false) ||
              (roomMap[b]?.isCorridor ?? false),
        ),
      );
    }

    // 1. Honor explicit required adjacencies first where a wall segment exists.
    final unmetAdjacencies = <(String, String)>[];
    for (final spec in specs) {
      for (final targetId in spec.requiredAdjacencyIds) {
        final wall = sharedWalls[(spec.id, targetId)] ?? sharedWalls[(targetId, spec.id)];
        if (wall != null && wall.overlapLength >= 0.7) {
          addDoor(wall);
        } else if (roomMap.containsKey(targetId)) {
          unmetAdjacencies.add((spec.id, targetId));
        }
      }
    }

    // 2. Link corridor spine cleanly to adjacent rooms if present.
    for (final entry in sharedWalls.entries) {
      final w = entry.value;
      if ((roomMap[w.roomAId]?.isCorridor ?? false) || (roomMap[w.roomBId]?.isCorridor ?? false)) {
        if (w.overlapLength >= 0.7) {
          addDoor(w, isCorridorLink: true);
        }
      }
    }

    // 3. Union-Find spanning connectivity pass across all remaining walls, sorted by widest overlap first
    final sortedWalls = sharedWalls.values.toList()
      ..sort((a, b) => b.overlapLength.compareTo(a.overlapLength));

    final parent = {for (final r in rooms) r.id: r.id};
    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }

    void union(String a, String b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (final edge in connectedEdges) {
      union(edge.$1, edge.$2);
    }

    for (final wall in sortedWalls) {
      if (wall.overlapLength < 0.65) continue;
      if (find(wall.roomAId) != find(wall.roomBId)) {
        addDoor(wall);
        if (adjacency[wall.roomAId]!.contains(wall.roomBId)) {
          union(wall.roomAId, wall.roomBId);
        }
      }
    }

    // Determine primary entry room for exterior doorway & reachability root
    ArchRoomRect entryRoom = rooms.first;
    for (final r in rooms) {
      final s = specMap[r.id];
      if ((s?.connectsToExterior ?? false) && r.exteriorSides.isNotEmpty) {
        entryRoom = r;
        break;
      }
    }
    if (entryRoom.exteriorSides.isEmpty) {
      entryRoom = rooms.firstWhere(
        (r) => r.exteriorSides.isNotEmpty,
        orElse: () => rooms.first,
      );
    }

    if (entryRoom.exteriorSides.isNotEmpty) {
      final side = _pickExteriorSide(entryRoom);
      final pos = _wallMidpoint(entryRoom, side);
      doorways.add(
        ArchDoorway(
          id: 'door_exterior',
          roomAId: entryRoom.id,
          roomBId: 'EXTERIOR',
          centerX: pos.$1,
          centerY: pos.$2,
          width: math.min(doorWidth * 1.1, _sideLength(entryRoom, side) * 0.65),
          spansAlongX: side == ArchWallSide.north || side == ArchWallSide.south,
          wallSideOnA: side,
          swingClearance: doorWidth,
          isExteriorEntrance: true,
        ),
      );
    }

    // BFS from entryRoom to verify 100% reachability
    final visited = <String>{entryRoom.id};
    final q = Queue<String>()..add(entryRoom.id);
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      for (final next in adjacency[cur] ?? const <String>{}) {
        if (visited.add(next)) q.add(next);
      }
    }
    final disconnected = {
      for (final r in rooms)
        if (!visited.contains(r.id)) r.id,
    };

    // 4. Exterior window placement on eligible perimeter walls
    final windows = <ArchWindowPlacement>[];
    var winSeq = 1;
    final entryDoor = doorways.where((d) => d.isExteriorEntrance).firstOrNull;
    for (final room in rooms) {
      if (room.isCorridor) continue;
      final spec = specMap[room.id];
      if (spec != null && !spec.preferredExteriorWindow) continue;
      for (final side in room.exteriorSides) {
        if (entryDoor != null &&
            entryDoor.roomAId == room.id &&
            entryDoor.wallSideOnA == side &&
            _sideLength(room, side) < doorWidth + windowWidth + 1.0) {
          continue;
        }
        final sideLen = _sideLength(room, side);
        if (sideLen >= windowWidth + 0.6) {
          final pos = _wallMidpoint(room, side);
          // Offset away from exterior entrance if sharing a long wall
          var wx = pos.$1;
          var wy = pos.$2;
          if (entryDoor != null && entryDoor.roomAId == room.id && entryDoor.wallSideOnA == side) {
            if (side == ArchWallSide.north || side == ArchWallSide.south) {
              wx = room.left + sideLen * 0.78;
            } else {
              wy = room.top + sideLen * 0.78;
            }
          }
          windows.add(
            ArchWindowPlacement(
              id: 'win_${winSeq++}',
              roomId: room.id,
              exteriorSide: side,
              centerX: wx,
              centerY: wy,
              width: math.min(windowWidth, sideLen * 0.5),
            ),
          );
          break; // 1 primary daylight window per eligible room
        }
      }
    }

    return ArchFloorplanResult(
      boundsWidth: boundsWidth,
      boundsDepth: boundsDepth,
      seed: seed,
      rooms: rooms,
      doorways: doorways,
      windows: windows,
      adjacencyGraph: adjacency,
      disconnectedRoomIds: disconnected,
      unmetAdjacencies: unmetAdjacencies,
    );
  }

  static ArchWallSide _pickExteriorSide(ArchRoomRect room) {
    for (final pref in const [
      ArchWallSide.south,
      ArchWallSide.west,
      ArchWallSide.east,
      ArchWallSide.north,
    ]) {
      if (room.exteriorSides.contains(pref)) return pref;
    }
    return ArchWallSide.south;
  }

  static double _sideLength(ArchRoomRect r, ArchWallSide side) {
    switch (side) {
      case ArchWallSide.north:
      case ArchWallSide.south:
        return r.width;
      case ArchWallSide.west:
      case ArchWallSide.east:
        return r.height;
    }
  }

  static (double, double) _wallMidpoint(ArchRoomRect r, ArchWallSide side) {
    switch (side) {
      case ArchWallSide.north:
        return (r.centerX, r.top);
      case ArchWallSide.south:
        return (r.centerX, r.bottom);
      case ArchWallSide.west:
        return (r.left, r.centerY);
      case ArchWallSide.east:
        return (r.right, r.centerY);
    }
  }
}
