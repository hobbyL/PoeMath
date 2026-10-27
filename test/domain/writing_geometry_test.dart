import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/writing_geometry.dart';

/// 从入库 fixture 读取真实 Make Me a Hanzi medians（y 轴已翻转）。
Map<String, List<List<Point<double>>>> _fixtureMedians() {
  final file = File('test/fixtures/writing_strokes_sample.json');
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final characters = raw['characters'] as Map<String, dynamic>;
  return {
    for (final entry in characters.entries)
      entry.key: [
        for (final stroke
            in (entry.value as Map<String, dynamic>)['medians'] as List)
          [
            for (final point in stroke as List)
              Point<double>(
                ((point as List)[0] as num).toDouble(),
                (point[1] as num).toDouble(),
              ),
          ],
      ],
  };
}

List<List<Point<double>>> _copy(List<List<Point<double>>> strokes) => [
      for (final stroke in strokes) List<Point<double>>.of(stroke),
    ];

/// 绕 stroke 起点旋转 [degrees]，用于构造"方向偏但其余维度接近"的笔迹。
List<Point<double>> _rotateStroke(List<Point<double>> stroke, double degrees) {
  final radians = degrees * pi / 180;
  final origin = stroke.first;
  final cosA = cos(radians);
  final sinA = sin(radians);
  return [
    for (final point in stroke)
      Point<double>(
        origin.x + (point.x - origin.x) * cosA - (point.y - origin.y) * sinA,
        origin.y + (point.x - origin.x) * sinA + (point.y - origin.y) * cosA,
      ),
  ];
}

List<Point<double>> _scaleTranslate(
  List<Point<double>> stroke,
  double scale,
  double dx,
  double dy,
) =>
    [
      for (final point in stroke)
        Point<double>(point.x * scale + dx, point.y * scale + dy),
    ];

void main() {
  final medians = _fixtureMedians();

  group('真实笔画数据：容差内通过', () {
    test('fixture 覆盖 山木水电子火 六字', () {
      expect(medians.keys.toSet(), {'山', '木', '水', '电', '子', '火'});
      for (final entry in medians.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} 应有笔画');
      }
    });

    test('参考笔迹原样提交全部通过', () {
      for (final entry in medians.entries) {
        final result = checkWriting(
          userStrokes: _copy(entry.value),
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isTrue, reason: '${entry.key}: $result');
        expect(result.firstBadStroke, isNull);
        expect(result.fault, isNull);
        expect(result.expectedStrokes, entry.value.length);
        expect(result.actualStrokes, entry.value.length);
      }
    });

    test('整体放大 3 倍并平移仍通过（序列包围盒归一化）', () {
      for (final entry in medians.entries) {
        final result = checkWriting(
          userStrokes: [
            for (final stroke in entry.value)
              _scaleTranslate(stroke, 3, 120, -40),
          ],
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isTrue, reason: '${entry.key}: $result');
      }
    });

    test('每点加入 ±0.3% 画布噪声仍通过', () {
      final random = Random(7);
      for (final entry in medians.entries) {
        final result = checkWriting(
          userStrokes: [
            for (final stroke in entry.value)
              [
                for (final point in stroke)
                  Point<double>(
                    point.x + (random.nextDouble() - 0.5) * 3,
                    point.y + (random.nextDouble() - 0.5) * 3,
                  ),
              ],
          ],
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isTrue, reason: '${entry.key}: $result');
      }
    });

    test('单笔 12° 方向偏移仍在容差内', () {
      for (final entry in medians.entries) {
        final user = _copy(entry.value);
        user[0] = _rotateStroke(user[0], 12);
        final result = checkWriting(
          userStrokes: user,
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isTrue, reason: '${entry.key}: $result');
      }
    });
  });

  group('真实笔画数据：典型错误被定位到具体笔画', () {
    test('第一笔首末反转判为方向错误，笔号 0', () {
      for (final entry in medians.entries) {
        final user = _copy(entry.value);
        user[0] = user[0].reversed.toList();
        final result = checkWriting(
          userStrokes: user,
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isFalse, reason: entry.key);
        expect(result.firstBadStroke, 0, reason: '${entry.key}: $result');
        expect(result.fault, StrokeFault.direction, reason: entry.key);
      }
    });

    test('末笔首末反转判为方向错误，笔号指向末笔', () {
      for (final entry in medians.entries) {
        final user = _copy(entry.value);
        final last = user.length - 1;
        final reversed = user[last].reversed.toList();
        // 只取首末反转后方向差异明显的笔画，避免点状笔画方向不稳定。
        final reference = StrokeGeometry.fromPolyline(entry.value[last]);
        if (_span(reference) < WritingTolerance.directionMinSpan) continue;
        user[last] = reversed;
        final result = checkWriting(
          userStrokes: user,
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isFalse, reason: entry.key);
        expect(result.firstBadStroke, last, reason: '${entry.key}: $result');
        expect(result.fault, StrokeFault.direction, reason: entry.key);
      }
    });

    test('相邻两笔互换顺序被拒绝', () {
      for (final entry in medians.entries) {
        final strokes = entry.value;
        final user = _copy(strokes);
        user[0] = List<Point<double>>.of(strokes[1]);
        user[1] = List<Point<double>>.of(strokes[0]);
        final result = checkWriting(
          userStrokes: user,
          referenceMedians: strokes,
        );
        expect(result.allPassed, isFalse, reason: '${entry.key}: $result');
        expect(result.firstBadStroke, isNotNull, reason: entry.key);
      }
    });

    test('少写一笔判为笔数错误且无具体笔号', () {
      for (final entry in medians.entries) {
        final user = _copy(entry.value)..removeAt(0);
        final result = checkWriting(
          userStrokes: user,
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isFalse);
        expect(result.fault, StrokeFault.strokesCount);
        expect(result.firstBadStroke, isNull);
        expect(result.actualStrokes, entry.value.length - 1);
        expect(result.expectedStrokes, entry.value.length);
      }
    });

    test('多写一笔判为笔数错误且无具体笔号', () {
      for (final entry in medians.entries) {
        final user = _copy(entry.value)
          ..add([const Point<double>(100, 100), const Point<double>(160, 160)]);
        final result = checkWriting(
          userStrokes: user,
          referenceMedians: entry.value,
        );
        expect(result.allPassed, isFalse);
        expect(result.fault, StrokeFault.strokesCount);
        expect(result.firstBadStroke, isNull);
        expect(result.actualStrokes, entry.value.length + 1);
      }
    });
  });

  group('合成数据：逐维度阈值', () {
    // 两笔"横"固定包围盒为 0~1，避免单笔归一化吃掉位置信息。
    const reference = [
      [Point<double>(0, 0), Point<double>(1, 0)],
      [Point<double>(0, 1), Point<double>(1, 1)],
    ];

    test('方向偏 15° 通过，偏 50° 判方向错误', () {
      final within = checkWriting(
        userStrokes: [
          [const Point<double>(0, 0), const Point<double>(0.966, 0.259)],
          reference[1],
        ],
        referenceMedians: reference,
      );
      expect(within.allPassed, isTrue, reason: '$within');

      final tooFar = checkWriting(
        userStrokes: [
          [const Point<double>(0, 0), const Point<double>(0.643, 0.766)],
          reference[1],
        ],
        referenceMedians: reference,
      );
      expect(tooFar.allPassed, isFalse);
      expect(tooFar.firstBadStroke, 0);
      expect(tooFar.fault, StrokeFault.direction);
    });

    test('起点平移 0.35 判起点错误', () {
      final result = checkWriting(
        userStrokes: [
          [
            const Point<double>(0.35, 0),
            const Point<double>(1, 0),
          ],
          reference[1],
        ],
        referenceMedians: reference,
      );
      expect(result.allPassed, isFalse);
      expect(result.firstBadStroke, 0);
      expect(result.fault, StrokeFault.startPoint);
    });

    test('终点偏移 0.4 判终点错误（方向仍在容差内）', () {
      final result = checkWriting(
        userStrokes: [
          [
            const Point<double>(0, 0),
            const Point<double>(1, 0.4),
          ],
          reference[1],
        ],
        referenceMedians: reference,
      );
      expect(result.allPassed, isFalse);
      expect(result.firstBadStroke, 0);
      expect(result.fault, StrokeFault.endPoint);
    });

    test('起终点正确但中间拱起判形状错误', () {
      final result = checkWriting(
        userStrokes: [
          [
            const Point<double>(0, 0),
            const Point<double>(0.5, 0.9),
            const Point<double>(1, 0),
          ],
          reference[1],
        ],
        referenceMedians: reference,
      );
      expect(result.allPassed, isFalse);
      expect(result.firstBadStroke, 0);
      expect(result.fault, StrokeFault.shape);
    });

    test('点状笔画写成往返长线判长度错误', () {
      const dotted = [
        [Point<double>(0.5, 0.5)],
        [Point<double>(0, 0), Point<double>(1, 0)],
      ];
      final result = checkWriting(
        userStrokes: [
          [
            const Point<double>(0.5, 0.5),
            const Point<double>(0.6, 0.65),
            const Point<double>(0.5, 0.5),
          ],
          dotted[1],
        ],
        referenceMedians: dotted,
      );
      expect(result.allPassed, isFalse);
      expect(result.firstBadStroke, 0);
      expect(result.fault, StrokeFault.length, reason: '$result');

      final dot = checkWriting(
        userStrokes: [
          [
            const Point<double>(0.5, 0.5),
            const Point<double>(0.52, 0.51),
          ],
          dotted[1],
        ],
        referenceMedians: dotted,
      );
      expect(dot.allPassed, isTrue, reason: '$dot');
    });

    test('点状参考笔画跳过方向判定', () {
      const dotted = [
        [Point<double>(0.5, 0.5)],
        [Point<double>(0, 0), Point<double>(1, 1)],
      ];
      final result = checkWriting(
        userStrokes: [
          [
            const Point<double>(0.5, 0.5),
            const Point<double>(0.45, 0.4),
          ],
          dotted[1],
        ],
        referenceMedians: dotted,
      );
      expect(result.allPassed, isTrue, reason: '$result');
    });
  });

  group('重采样与归一化工具', () {
    test('重采样保留首末点并等分弧长', () {
      final points = resamplePolyline(
        const [Point<double>(0, 0), Point<double>(10, 0)],
        5,
      );
      expect(points.first, const Point<double>(0, 0));
      expect(points.last, const Point<double>(10, 0));
      expect(points.map((p) => p.x).toList(), [0, 2.5, 5, 7.5, 10]);
    });

    test('单点折线重采样为同一点的重复', () {
      final points = resamplePolyline(const [Point<double>(3, 4)], 4);
      expect(points.length, 4);
      expect(points.every((p) => p.x == 3 && p.y == 4), isTrue);
    });

    test('零长度折线不产生 NaN', () {
      final points = resamplePolyline(
        const [Point<double>(1, 1), Point<double>(1, 1)],
        3,
      );
      expect(points.every((p) => p.x == 1 && p.y == 1), isTrue);
    });

    test('空点列抛参数错误', () {
      expect(
        () => resamplePolyline(const <Point<double>>[], 4),
        throwsArgumentError,
      );
    });

    test('序列归一化等比缩放并居中到单位方框', () {
      final normalized = normalizeStrokeSequence([
        const [Point<double>(10, 20), Point<double>(30, 40)],
      ]);
      expect(normalized.single.first, const Point<double>(0, 0));
      expect(normalized.single.last, const Point<double>(1, 1));
    });

    test('归一化保留笔画间相对位置', () {
      final normalized = normalizeStrokeSequence([
        const [Point<double>(0, 0), Point<double>(10, 0)],
        const [Point<double>(0, 10), Point<double>(10, 10)],
      ]);
      expect(normalized[0].first.y, closeTo(0, 1e-9));
      expect(normalized[1].first.y, closeTo(1, 1e-9));
    });

    test('全部点重合时归一化到方框中心', () {
      final normalized = normalizeStrokeSequence([
        const [Point<double>(5, 5)],
      ]);
      expect(normalized.single.single, const Point<double>(0.5, 0.5));
    });

    test('StrokeGeometry 提取方向角与路径长', () {
      final geometry = StrokeGeometry.fromPolyline(
        const [Point<double>(0, 0), Point<double>(3, 4)],
      );
      expect(geometry.start, const Point<double>(0, 0));
      expect(geometry.end, const Point<double>(3, 4));
      expect(geometry.directionAngle, closeTo(atan2(4, 3), 1e-9));
      expect(geometry.pathLength, closeTo(5, 1e-9));
      expect(geometry.points.length, WritingTolerance.resamplePoints);
    });
  });
}

double _span(StrokeGeometry geometry) {
  final dx = geometry.end.x - geometry.start.x;
  final dy = geometry.end.y - geometry.start.y;
  return sqrt(dx * dx + dy * dy);
}