import 'dart:math';

typedef PuzzlePoint = Point<double>;

/// 整字纸面的一个碎片。坐标始终相对于单位正方形，与屏幕大小无关。
class CharacterPuzzlePiece {
  CharacterPuzzlePiece({
    required this.id,
    required List<PuzzlePoint> outline,
    required this.inkPoint,
  }) : outline = List.unmodifiable(outline),
       bounds = _bounds(outline);

  final int id;
  final List<PuzzlePoint> outline;

  /// 分片的生成点来自真实字形内部，每片都应保留笔画。
  final PuzzlePoint inkPoint;
  final Rectangle<double> bounds;

  bool contains(PuzzlePoint point) {
    var inside = false;
    for (var i = 0, j = outline.length - 1; i < outline.length; j = i++) {
      final a = outline[i];
      final b = outline[j];
      if ((a.y > point.y) != (b.y > point.y) &&
          point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  double get area {
    var twice = 0.0;
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      twice += a.x * b.y - b.x * a.y;
    }
    return twice.abs() / 2;
  }
}

class CharacterPuzzleLayout {
  CharacterPuzzleLayout({
    required List<CharacterPuzzlePiece> pieces,
    required List<int> trayOrder,
  }) : pieces = List.unmodifiable(pieces),
       trayOrder = List.unmodifiable(trayOrder);

  final List<CharacterPuzzlePiece> pieces;
  final List<int> trayOrder;
}

/// 从实际笔画内的点生成不等大的碎片，而不是把笔画或部首当作拼块。
///
/// 先构造覆盖纸面的 Voronoi 分区，再为相邻分区生成同一条撕裂折线。
/// 共边只计算一次、反向复用，因此碎片拼回去不会留下缝隙或重叠。
CharacterPuzzleLayout createCharacterPuzzle({
  required List<PuzzlePoint> inkPoints,
  required int seed,
  int pieceCount = 6,
}) {
  if (pieceCount < 2) throw ArgumentError.value(pieceCount, 'pieceCount');
  final unique = <String, PuzzlePoint>{};
  for (final point in inkPoints) {
    if (point.x.isFinite &&
        point.y.isFinite &&
        point.x > 0 &&
        point.x < 1 &&
        point.y > 0 &&
        point.y < 1) {
      unique[_pointKey(point)] = point;
    }
  }
  final candidates = unique.values.toList();
  if (candidates.length < pieceCount) {
    throw ArgumentError('字形内的采样点不足以分片');
  }
  final random = Random(seed);
  final sites = <PuzzlePoint>[candidates[random.nextInt(candidates.length)]];
  while (sites.length < pieceCount) {
    var best = candidates.first;
    var bestScore = -1.0;
    for (final candidate in candidates) {
      final distance = sites
          .map((site) => candidate.squaredDistanceTo(site))
          .reduce(min);
      // 在足够分散的基础上保留大小差异，不生成等宽、等面积的格子。
      final score = distance * (0.65 + random.nextDouble() * 0.7);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    sites.add(best);
  }

  final cells = <List<PuzzlePoint>>[];
  for (final site in sites) {
    var polygon = <PuzzlePoint>[
      const Point(0.0, 0.0),
      const Point(1.0, 0.0),
      const Point(1.0, 1.0),
      const Point(0.0, 1.0),
    ];
    for (final other in sites) {
      if (identical(site, other)) continue;
      final normal = other - site;
      final limit =
          (other.x * other.x +
              other.y * other.y -
              site.x * site.x -
              site.y * site.y) /
          2;
      polygon = _clip(polygon, normal, limit);
    }
    cells.add(polygon);
  }

  final edges = <String, List<PuzzlePoint>>{};
  final pieces = <CharacterPuzzlePiece>[];
  for (var i = 0; i < cells.length; i++) {
    final outline = <PuzzlePoint>[];
    final cell = cells[i];
    for (var j = 0; j < cell.length; j++) {
      final a = cell[j];
      final b = cell[(j + 1) % cell.length];
      final aKey = _pointKey(a);
      final bKey = _pointKey(b);
      final forward = aKey.compareTo(bKey) < 0;
      final start = forward ? a : b;
      final end = forward ? b : a;
      final key = forward ? '$aKey/$bKey' : '$bKey/$aKey';
      final edge = edges.putIfAbsent(
        key,
        () => _tearEdge(start, end, cells, sites, random),
      );
      final ordered = forward ? edge : edge.reversed.toList();
      outline.addAll(ordered.take(ordered.length - 1));
    }
    pieces.add(
      CharacterPuzzlePiece(id: i, outline: outline, inkPoint: sites[i]),
    );
  }
  final order = List.generate(pieceCount, (i) => i)..shuffle(random);
  return CharacterPuzzleLayout(pieces: pieces, trayOrder: order);
}

List<PuzzlePoint> _clip(
  List<PuzzlePoint> polygon,
  PuzzlePoint normal,
  double limit,
) {
  final result = <PuzzlePoint>[];
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final da = a.x * normal.x + a.y * normal.y - limit;
    final db = b.x * normal.x + b.y * normal.y - limit;
    if (da <= 0) result.add(a);
    if ((da <= 0) != (db <= 0)) {
      final fraction = da / (da - db);
      result.add(
        Point(a.x + (b.x - a.x) * fraction, a.y + (b.y - a.y) * fraction),
      );
    }
  }
  return result;
}

List<PuzzlePoint> _tearEdge(
  PuzzlePoint a,
  PuzzlePoint b,
  List<List<PuzzlePoint>> cells,
  List<PuzzlePoint> sites,
  Random random,
) {
  final delta = b - a;
  final length = delta.magnitude;
  // 纸张外框保持平直；三片交界处也保持原端点，避免错缝。
  if (length < 1e-8 ||
      ((a.x - b.x).abs() < 1e-8 && (a.x < 1e-8 || a.x > 1 - 1e-8)) ||
      ((a.y - b.y).abs() < 1e-8 && (a.y < 1e-8 || a.y > 1 - 1e-8))) {
    return [a, b];
  }
  final middle = (a + b) * 0.5;
  var clearance = length;
  for (final cell in cells) {
    for (var i = 0; i < cell.length; i++) {
      final c = cell[i];
      final d = cell[(i + 1) % cell.length];
      final edge = d - c;
      if (edge.magnitude < 1e-8) continue;
      final distance =
          ((middle.x - c.x) * edge.y - (middle.y - c.y) * edge.x).abs() /
          edge.magnitude;
      if (distance > 1e-7) clearance = min(clearance, distance);
    }
  }
  // 不让撕裂边侵入任何生成点，确保每片仍然有真实笔画。
  for (final site in sites) {
    final distance =
        ((site.x - a.x) * delta.y - (site.y - a.y) * delta.x).abs() / length;
    if (distance > 1e-7) clearance = min(clearance, distance);
  }
  final amplitude = min(0.014, min(length * 0.05, clearance * 0.12));
  final normal = Point(-delta.y / length, delta.x / length);
  final sign = random.nextBool() ? 1.0 : -1.0;
  return [
    a,
    for (var i = 1; i <= 4; i++)
      a +
          delta * (i / 5) +
          normal *
              (amplitude *
                  (0.6 + random.nextDouble() * 0.4) *
                  (i.isOdd ? sign : -sign)),
    b,
  ];
}

String _pointKey(PuzzlePoint point) =>
    '${point.x.toStringAsFixed(7)},${point.y.toStringAsFixed(7)}';

Rectangle<double> _bounds(List<PuzzlePoint> points) {
  final left = points.map((p) => p.x).reduce(min);
  final top = points.map((p) => p.y).reduce(min);
  final right = points.map((p) => p.x).reduce(max);
  final bottom = points.map((p) => p.y).reduce(max);
  return Rectangle(left, top, right - left, bottom - top);
}
