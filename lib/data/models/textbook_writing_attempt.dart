import 'dart:math';

import 'package:poemath/domain/writing_geometry.dart';

enum WritingAttemptKind { trace, free, puzzle }

/// 一次完成时冻结的作品。坐标相对于当次画布，不随回看尺寸改变。
class WritingAttempt {
  WritingAttempt({
    required this.id,
    required this.kind,
    required DateTime startedAt,
    required DateTime completedAt,
    List<String> referenceStrokes = const [],
    List<List<Point<double>>> strokes = const [],
    this.strokeWidth = 0,
    this.puzzle,
  }) : startedAt = startedAt.toUtc(),
       completedAt = completedAt.toUtc(),
       referenceStrokes = List.unmodifiable(referenceStrokes),
       strokes = _freeze(strokes) {
    if (id.trim().isEmpty ||
        id.length > 512 ||
        this.completedAt.isBefore(this.startedAt) ||
        this.referenceStrokes.length > maxStrokes ||
        this.referenceStrokes.any((s) => s.isEmpty || s.length > 32768) ||
        this.referenceStrokes.fold<int>(0, (n, s) => n + s.length) > 262144 ||
        this.strokes.length > maxStrokes ||
        this.strokes.any(
          (s) => s.isEmpty || s.length > maxPointsPerStroke || !_finite(s),
        ) ||
        !strokeWidth.isFinite ||
        (kind == WritingAttemptKind.puzzle
            ? puzzle == null ||
                  this.referenceStrokes.isEmpty ||
                  this.strokes.isNotEmpty ||
                  strokeWidth != 0
            : puzzle != null || strokeWidth <= 0 || strokeWidth > 1) ||
        (kind == WritingAttemptKind.trace && this.referenceStrokes.isEmpty)) {
      throw const FormatException('练习作品格式损坏');
    }
  }

  static const maxStrokes = 256;
  static const maxPointsPerStroke = 512;
  static const maxAttempts = 20000;

  final String id;
  final WritingAttemptKind kind;
  final DateTime startedAt, completedAt;
  final List<String> referenceStrokes;
  final List<List<Point<double>>> strokes;
  final double strokeWidth;
  final WritingPuzzleResult? puzzle;

  int get durationSeconds => completedAt.difference(startedAt).inSeconds;

  /// 保留笔画位置及笔宽；长笔画按弧长采样，短笔画逐点保存。
  factory WritingAttempt.captureWriting({
    required String id,
    required WritingAttemptKind kind,
    required DateTime startedAt,
    required DateTime completedAt,
    required List<List<Point<double>>> strokes,
    required double canvasSide,
    List<String> referenceStrokes = const [],
  }) {
    if (!canvasSide.isFinite || canvasSide < 3 || strokes.length > maxStrokes) {
      throw const FormatException('练习画布或笔迹超出范围');
    }
    final normalized = <List<Point<double>>>[];
    for (final stroke in strokes) {
      if (stroke.isEmpty || !_finite(stroke)) {
        throw const FormatException('练习笔迹格式损坏');
      }
      final points = stroke.length > maxPointsPerStroke
          ? resamplePolyline(stroke, maxPointsPerStroke)
          : stroke;
      normalized.add([
        for (final point in points)
          Point<double>(
            _rounded(point.x / canvasSide),
            _rounded(point.y / canvasSide),
          ),
      ]);
    }
    return WritingAttempt(
      id: id,
      kind: kind,
      startedAt: startedAt,
      completedAt: completedAt,
      referenceStrokes: referenceStrokes,
      strokes: normalized,
      strokeWidth: 3 / canvasSide,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'id': id,
    'kind': kind.name,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'referenceStrokes': referenceStrokes,
    'strokes': _encodePoints(strokes),
    'strokeWidth': strokeWidth,
    'puzzle': puzzle?.toJson(),
  };

  factory WritingAttempt.fromJson(Map<String, dynamic> json) {
    final kind = WritingAttemptKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final references = json['referenceStrokes'];
    if (json['v'] != 1 ||
        json['id'] is! String ||
        kind == null ||
        references is! List ||
        references.length > maxStrokes ||
        references.any((s) => s is! String)) {
      throw const FormatException('练习作品格式损坏');
    }
    return WritingAttempt(
      id: json['id'] as String,
      kind: kind,
      startedAt: _date(json['startedAt']),
      completedAt: _date(json['completedAt']),
      referenceStrokes: references.cast<String>(),
      strokes: _decodePoints(json['strokes'], maxStrokes, maxPointsPerStroke),
      strokeWidth: _number(json['strokeWidth']),
      puzzle: json['puzzle'] == null
          ? null
          : WritingPuzzleResult.fromJson(_map(json['puzzle'])),
    );
  }
}

/// 拼装完成时的实际碎片及完成顺序，不重新随机生成历史布局。
class WritingPuzzleResult {
  WritingPuzzleResult({
    required List<List<Point<double>>> pieces,
    required List<int> placementOrder,
    required this.hintEnabled,
    required this.wrongPlacements,
  }) : pieces = _freeze(pieces),
       placementOrder = List.unmodifiable(placementOrder) {
    if (this.pieces.length < 2 ||
        this.pieces.length > 12 ||
        this.pieces.any(
          (p) =>
              p.length < 3 ||
              p.length > 512 ||
              !_finite(p) ||
              p.any(
                (v) =>
                    v.x < -1e-8 ||
                    v.x > 1 + 1e-8 ||
                    v.y < -1e-8 ||
                    v.y > 1 + 1e-8,
              ),
        ) ||
        this.placementOrder.length != this.pieces.length ||
        this.placementOrder.toSet().length != this.pieces.length ||
        this.placementOrder.any((id) => id < 0 || id >= this.pieces.length) ||
        wrongPlacements < 0) {
      throw const FormatException('拼装作品格式损坏');
    }
  }

  final List<List<Point<double>>> pieces;
  final List<int> placementOrder;
  final bool hintEnabled;
  final int wrongPlacements;

  Map<String, dynamic> toJson() => {
    'pieces': _encodePoints(pieces),
    'placementOrder': placementOrder,
    'hintEnabled': hintEnabled,
    'wrongPlacements': wrongPlacements,
  };

  factory WritingPuzzleResult.fromJson(Map<String, dynamic> json) {
    final order = json['placementOrder'];
    final wrong = json['wrongPlacements'];
    if (order is! List ||
        order.length > 12 ||
        order.any((id) => id is! int) ||
        json['hintEnabled'] is! bool ||
        wrong is! int) {
      throw const FormatException('拼装作品格式损坏');
    }
    return WritingPuzzleResult(
      pieces: _decodePoints(json['pieces'], 12, 512),
      placementOrder: order.cast<int>(),
      hintEnabled: json['hintEnabled'] as bool,
      wrongPlacements: wrong,
    );
  }
}

List<List<Point<double>>> _freeze(List<List<Point<double>>> lines) =>
    List.unmodifiable(
      lines.map((line) => List<Point<double>>.unmodifiable(line)),
    );

bool _finite(List<Point<double>> points) => points.every(
  (p) => p.x.isFinite && p.y.isFinite && p.x.abs() <= 1e6 && p.y.abs() <= 1e6,
);

double _rounded(double value) => (value * 100000).round() / 100000;

List<List<List<double>>> _encodePoints(List<List<Point<double>>> lines) => [
  for (final line in lines)
    [
      for (final point in line) [point.x, point.y],
    ],
];

List<List<Point<double>>> _decodePoints(
  Object? raw,
  int maxLines,
  int maxPoints,
) {
  if (raw is! List || raw.length > maxLines) {
    throw const FormatException('作品点列超出范围');
  }
  return [
    for (final line in raw)
      if (line is List && line.isNotEmpty && line.length <= maxPoints)
        [
          for (final point in line)
            if (point is List && point.length == 2)
              Point<double>(_number(point[0]), _number(point[1]))
            else
              throw const FormatException('作品坐标格式损坏'),
        ]
      else
        throw const FormatException('作品点列格式损坏'),
  ];
}

double _number(Object? value) {
  if (value is! num || !value.isFinite || value.abs() > 1e6) {
    throw const FormatException('作品数值格式损坏');
  }
  return value.toDouble();
}

DateTime _date(Object? value) {
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null || date.toUtc().toIso8601String() != value) {
    throw const FormatException('作品时间格式损坏');
  }
  return date.toUtc();
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('作品数据必须为对象');
  }
  return value;
}
