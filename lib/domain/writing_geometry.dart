import 'dart:math';

/// 书写几何比对的容差常量表。
///
/// 儿童字迹方差大，阈值从宽；所有调参集中在这里，不散落到比对逻辑中。
/// 判定失败只作"教练提示"（指出第几笔），不构成对孩子的评价。
class WritingTolerance {
  const WritingTolerance._();

  /// 单笔方向夹角上限（度）。
  static const directionDeg = 40.0;
  static const directionRadians = directionDeg * pi / 180;

  /// 起点在归一化单位方框内的允许偏差。
  static const startDist = 0.25;

  /// 终点允许偏差（收笔抖动更大，从宽）。
  static const endDist = 0.30;

  /// 重采样后逐点平均距离上限（形状）。
  static const shapeAvgDist = 0.20;

  /// 笔画路径长度比允许区间（防"点成短线"或"线拉太长"）。
  static const lengthRatioMin = 0.5;
  static const lengthRatioMax = 2.0;

  /// 每笔弧长均匀重采样点数。
  static const resamplePoints = 16;

  /// 首末点距离小于该值的笔画视为"点状"：方向不稳定，跳过方向判定。
  static const directionMinSpan = 0.05;

  /// 参考笔画长度小于该值按"点"处理，只限制孩子笔画不能过长。
  static const dotPathLength = 0.02;

  /// 点状参考笔画允许的孩子笔画最大长度。
  static const dotUserMaxLength = 0.15;
}

/// 单笔失败类型；UI 据此生成"第 N 笔……"的正向提示。
enum StrokeFault {
  /// 笔数不符（此时没有具体笔号）。
  strokesCount,
  direction,
  startPoint,
  endPoint,
  shape,
  length,
}

/// 整字几何比对结果。
class WritingCheckResult {
  const WritingCheckResult({
    required this.allPassed,
    required this.firstBadStroke,
    required this.fault,
    required this.expectedStrokes,
    required this.actualStrokes,
  });

  /// 全部笔画通过。
  final bool allPassed;

  /// 首个失败笔画的 0 基序号；笔数不符或全对时为 null。
  final int? firstBadStroke;

  /// 失败类型；全对时为 null。
  final StrokeFault? fault;

  final int expectedStrokes;
  final int actualStrokes;

  @override
  String toString() => allPassed
      ? 'WritingCheckResult(passed, $actualStrokes strokes)'
      : 'WritingCheckResult(failed, firstBadStroke=$firstBadStroke, '
          'fault=${fault?.name}, $actualStrokes/$expectedStrokes strokes)';
}

/// 单笔几何特征（坐标为包围盒归一化后的单位方框坐标）。
class StrokeGeometry {
  const StrokeGeometry({
    required this.points,
    required this.start,
    required this.end,
    required this.directionAngle,
    required this.pathLength,
  });

  /// 弧长均匀重采样后的点列（[WritingTolerance.resamplePoints] 点）。
  final List<Point<double>> points;
  final Point<double> start;
  final Point<double> end;

  /// 首末点向量角（弧度，atan2）。
  final double directionAngle;

  /// 折线路径总长（归一化坐标）。
  final double pathLength;

  /// 由原始折线构建：先弧长重采样，再提取特征。
  factory StrokeGeometry.fromPolyline(List<Point<double>> raw) {
    final points = resamplePolyline(raw, WritingTolerance.resamplePoints);
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += _distance(points[i - 1], points[i]);
    }
    final start = points.first;
    final end = points.last;
    return StrokeGeometry(
      points: points,
      start: start,
      end: end,
      directionAngle: atan2(end.y - start.y, end.x - start.x),
      pathLength: length,
    );
  }
}

/// 按弧长均匀重采样折线到 [count] 点；首末点保留。
///
/// 单点折线（点状笔画）返回 [count] 个相同点；零长度折线同理。
List<Point<double>> resamplePolyline(List<Point<double>> points, int count) {
  if (count < 2) {
    throw ArgumentError.value(count, 'count', '重采样点数至少为 2');
  }
  if (points.isEmpty) {
    throw ArgumentError.value(points, 'points', '笔画点列不能为空');
  }
  if (points.length == 1) {
    return List<Point<double>>.filled(count, points.single);
  }
  final cumulative = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    cumulative[i] = cumulative[i - 1] + _distance(points[i - 1], points[i]);
  }
  final total = cumulative.last;
  if (total <= 0) {
    return List<Point<double>>.filled(count, points.first);
  }
  final result = <Point<double>>[];
  var segment = 1;
  for (var i = 0; i < count; i++) {
    final target = total * i / (count - 1);
    while (segment < points.length - 1 && cumulative[segment] < target) {
      segment++;
    }
    final before = cumulative[segment - 1];
    final span = cumulative[segment] - before;
    final t = span <= 0 ? 0.0 : (target - before) / span;
    result.add(
      Point<double>(
        points[segment - 1].x + t * (points[segment].x - points[segment - 1].x),
        points[segment - 1].y + t * (points[segment].y - points[segment - 1].y),
      ),
    );
  }
  return result;
}

/// 把整组笔画按**序列包围盒**等比缩放并居中到单位方框 [0,1]²。
///
/// 序列级（而非单笔级）归一化保留笔画之间的相对位置，起点/终点判定才有意义。
/// 等比缩放消除大小差异；居中消除书写位置差异。
List<List<Point<double>>> normalizeStrokeSequence(
  List<List<Point<double>>> strokes,
) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  var hasPoint = false;
  for (final stroke in strokes) {
    for (final point in stroke) {
      hasPoint = true;
      minX = min(minX, point.x);
      minY = min(minY, point.y);
      maxX = max(maxX, point.x);
      maxY = max(maxY, point.y);
    }
  }
  if (!hasPoint) {
    return [
      for (final stroke in strokes) List<Point<double>>.of(stroke),
    ];
  }
  final scale = max(maxX - minX, maxY - minY);
  final centerX = (minX + maxX) / 2;
  final centerY = (minY + maxY) / 2;
  if (scale <= 0) {
    // 全部点重合（单点字/单点笔画）：统一落到方框中心。
    return [
      for (final stroke in strokes)
        [
          for (final _ in stroke) const Point<double>(0.5, 0.5),
        ],
    ];
  }
  return [
    for (final stroke in strokes)
      [
        for (final point in stroke)
          Point<double>(
            0.5 + (point.x - centerX) / scale,
            0.5 + (point.y - centerY) / scale,
          ),
      ],
  ];
}

/// 已知目标字的几何比对：孩子笔画序列 vs 参考 medians。
///
/// 流程：笔数 → 序列包围盒归一化 → 逐笔（方向 → 起点 → 终点 → 形状 → 长度），
/// 首个失败即短路返回，供 UI 指明"第几笔不对"。纯函数、同步、微秒级。
WritingCheckResult checkWriting({
  required List<List<Point<double>>> userStrokes,
  required List<List<Point<double>>> referenceMedians,
}) {
  final expected = referenceMedians.length;
  final actual = userStrokes.length;
  if (expected != actual) {
    return WritingCheckResult(
      allPassed: false,
      firstBadStroke: null,
      fault: StrokeFault.strokesCount,
      expectedStrokes: expected,
      actualStrokes: actual,
    );
  }
  final reference = normalizeStrokeSequence(referenceMedians);
  final user = normalizeStrokeSequence(userStrokes);
  for (var i = 0; i < reference.length; i++) {
    if (reference[i].isEmpty || user[i].isEmpty) {
      return WritingCheckResult(
        allPassed: false,
        firstBadStroke: i,
        fault: StrokeFault.shape,
        expectedStrokes: expected,
        actualStrokes: actual,
      );
    }
    final fault = _compareStroke(reference[i], user[i]);
    if (fault != null) {
      return WritingCheckResult(
        allPassed: false,
        firstBadStroke: i,
        fault: fault,
        expectedStrokes: expected,
        actualStrokes: actual,
      );
    }
  }
  return WritingCheckResult(
    allPassed: true,
    firstBadStroke: null,
    fault: null,
    expectedStrokes: expected,
    actualStrokes: actual,
  );
}

StrokeFault? _compareStroke(
  List<Point<double>> referencePoints,
  List<Point<double>> userPoints,
) {
  final reference = StrokeGeometry.fromPolyline(referencePoints);
  final user = StrokeGeometry.fromPolyline(userPoints);

  // 方向：点状笔画（如"丶"）方向不稳定，跳过；其余按首末点向量夹角。
  final referenceSpan = _distance(reference.start, reference.end);
  final userSpan = _distance(user.start, user.end);
  if (referenceSpan >= WritingTolerance.directionMinSpan &&
      userSpan >= WritingTolerance.directionMinSpan &&
      _angleDifference(reference.directionAngle, user.directionAngle) >
          WritingTolerance.directionRadians) {
    return StrokeFault.direction;
  }

  if (_distance(reference.start, user.start) > WritingTolerance.startDist) {
    return StrokeFault.startPoint;
  }
  if (_distance(reference.end, user.end) > WritingTolerance.endDist) {
    return StrokeFault.endPoint;
  }

  var sum = 0.0;
  for (var i = 0; i < reference.points.length; i++) {
    sum += _distance(reference.points[i], user.points[i]);
  }
  if (sum / reference.points.length > WritingTolerance.shapeAvgDist) {
    return StrokeFault.shape;
  }

  if (reference.pathLength <= WritingTolerance.dotPathLength) {
    if (user.pathLength > WritingTolerance.dotUserMaxLength) {
      return StrokeFault.length;
    }
  } else {
    final ratio = user.pathLength / reference.pathLength;
    if (ratio < WritingTolerance.lengthRatioMin ||
        ratio > WritingTolerance.lengthRatioMax) {
      return StrokeFault.length;
    }
  }
  return null;
}

double _distance(Point<double> a, Point<double> b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return sqrt(dx * dx + dy * dy);
}

/// 两角度的最小夹角（弧度，[0, π]）。
double _angleDifference(double a, double b) {
  var difference = (a - b).abs() % (2 * pi);
  if (difference > pi) difference = 2 * pi - difference;
  return difference;
}
