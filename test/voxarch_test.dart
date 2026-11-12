import 'package:test/test.dart';
import 'package:voxarch/voxarch.dart';

void main() {
  test('ArchFloorplanSolver subdivides residential program deterministically with 100% connectivity', () {
    const specs = [
      ArchRoomSpec(
        id: 'foyer',
        role: 'entry',
        targetWeight: 0.7,
        connectsToExterior: true,
        requiredAdjacencyIds: ['living'],
      ),
      ArchRoomSpec(id: 'living', role: 'common', targetWeight: 1.8, requiredAdjacencyIds: ['kitchen']),
      ArchRoomSpec(id: 'kitchen', role: 'utility', targetWeight: 1.1),
      ArchRoomSpec(id: 'bedroom_a', role: 'sleep', targetWeight: 1.2),
      ArchRoomSpec(id: 'bath', role: 'wet', targetWeight: 0.6, preferredExteriorWindow: false),
    ];

    final solver = ArchFloorplanSolver(
      boundsWidth: 16.0,
      boundsDepth: 12.0,
      carveCentralCorridor: false,
    );

    final a = solver.solve(specs, seed: 42);
    final b = solver.solve(specs, seed: 42);
    expect(a.rooms.length, 5);
    expect(a.isFullyConnected, isTrue);
    expect(a.totalArea, closeTo(16.0 * 12.0, 1e-4));
    expect(a.doorways.any((d) => d.isExteriorEntrance), isTrue);
    expect(a.shortestRoomPath('foyer', 'bedroom_a'), isNotEmpty);

    for (var i = 0; i < a.rooms.length; i++) {
      expect(a.rooms[i].x, closeTo(b.rooms[i].x, 1e-9));
      expect(a.rooms[i].width, closeTo(b.rooms[i].width, 1e-9));
    }
  });

  test('ArchFloorplanSolver carves central corridor spine linking north and south wings', () {
    const specs = [
      ArchRoomSpec(id: 'office_n1', role: 'office', connectsToExterior: true),
      ArchRoomSpec(id: 'office_n2', role: 'office'),
      ArchRoomSpec(id: 'office_s1', role: 'office'),
      ArchRoomSpec(id: 'vault_s2', role: 'vault', preferredExteriorWindow: false),
    ];

    final solver = ArchFloorplanSolver(
      boundsWidth: 18.0,
      boundsDepth: 12.0,
      carveCentralCorridor: true,
      corridorWidth: 2.0,
    );

    final res = solver.solve(specs, seed: 7);
    expect(res.rooms.any((r) => r.isCorridor), isTrue);
    expect(res.isFullyConnected, isTrue);
    expect(res.doorways.where((d) => d.isCorridorLink).length, greaterThanOrEqualTo(3));
    expect(res.windows.any((w) => w.roomId == 'vault_s2'), isFalse);
  });

  test('ArchFloorplanResult emits ASCII preview and preserves positive room dimensions', () {
    const specs = [
      ArchRoomSpec(id: 'hall', targetWeight: 2.0, connectsToExterior: true),
      ArchRoomSpec(id: 'armory', targetWeight: 1.0),
      ArchRoomSpec(id: 'lab', targetWeight: 1.0),
    ];

    final res = ArchFloorplanSolver(boundsWidth: 14.0, boundsDepth: 10.0).solve(specs, seed: 99);
    for (final room in res.rooms) {
      expect(room.width, greaterThan(1.0));
      expect(room.height, greaterThan(1.0));
    }
    final ascii = res.toAsciiPreview(cols: 28, rows: 10);
    expect(ascii.split('\n').length, 10);
    expect(res.windows, isNotEmpty);
  });
}
