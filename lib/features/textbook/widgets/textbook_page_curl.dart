import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一张纸绕向观察者凸起的圆柱卷动；坐标始终相对于完整预览区域。
class TextbookPageCurl {
  TextbookPageCurl({
    required this.size,
    required this.progress,
    this.doublePage = false,
  });

  final Size size;
  final double progress;
  final bool doublePage;

  double get spine => doublePage ? size.width / 2 : 0;
  double get leafWidth => size.width - spine;
  double get radius => leafWidth * 0.12 * math.sin(math.pi * progress);
  double get tilt => 0.14 * math.sin(math.pi * progress);
  double get fold => size.width - leafWidth * progress;
  bool get active => progress > 0 && progress < 1 && !size.isEmpty;

  /// 纸面未卷起、圆柱弯曲、已翻到纸背的三个连续区间。
  ({Offset position, double angle, double height}) project(Offset source) {
    if (progress <= 0 || size.isEmpty) {
      return (position: source, angle: 0, height: 0);
    }
    final cosine = math.cos(tilt);
    final sine = math.sin(tilt);
    final dx = source.dx - fold;
    final dy = source.dy - size.height / 2;
    final distance = dx * cosine + dy * sine;
    if (distance <= 0) return (position: source, angle: 0, height: 0);
    final along = -dx * sine + dy * cosine;
    final angle = radius > leafWidth * 0.00001
        ? (distance / radius).clamp(0.0, math.pi)
        : math.pi;
    final curved = distance < math.pi * radius
        ? radius * math.sin(angle)
        : -(distance - math.pi * radius);
    final height = radius * (1 - math.cos(angle));
    final scale = 1 / (1 - height / leafWidth * 0.32);
    final x = fold + curved * cosine - along * sine;
    final y = size.height / 2 + curved * sine + along * cosine;
    return (
      position: Offset(
        spine + (x - spine) * scale,
        size.height / 2 + (y - size.height / 2) * scale,
      ),
      angle: angle,
      height: height,
    );
  }

  Path flatClip(Rect source) {
    if (!active) return Path()..addRect(source);
    double edge(double y) => fold - (y - size.height / 2) * math.tan(tilt);
    return Path()
      ..moveTo(source.left, source.top)
      ..lineTo(edge(source.top).clamp(source.left, source.right), source.top)
      ..lineTo(
        edge(source.bottom).clamp(source.left, source.right),
        source.bottom,
      )
      ..lineTo(source.left, source.bottom)
      ..close();
  }

  late final mesh = meshFor(
    Rect.fromLTRB(spine, 0, size.width, size.height),
  );

  /// 统一绕向，重叠的正面、纸背共同构成遮挡轮廓，不能用 evenOdd 抵消。
  late final coverage = () {
    final path = Path();
    if (doublePage) {
      path.addRect(Rect.fromLTWH(0, 0, spine, size.height));
    }
    for (var i = 0; i < mesh.indices.length; i += 3) {
      final a = mesh.positions[mesh.indices[i]];
      final b = mesh.positions[mesh.indices[i + 1]];
      final c = mesh.positions[mesh.indices[i + 2]];
      final clockwise =
          (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx) >= 0;
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(clockwise ? b.dx : c.dx, clockwise ? b.dy : c.dy)
        ..lineTo(clockwise ? c.dx : b.dx, clockwise ? c.dy : b.dy)
        ..close();
    }
    return path;
  }();

  late final revealed = Path.combine(
    PathOperation.difference,
    Path()..addRect(Offset.zero & size),
    coverage,
  );

  /// 弯曲区密集采样，平面区域只需端点；随倾斜逐行对齐圆柱。
  TextbookCurlMesh meshFor(Rect source, {bool reverse = false}) {
    const segments = 32;
    const rows = 8;
    const columns = segments + 3;
    final positions = <Offset>[];
    final texture = <Offset>[];
    final angles = <double>[];
    for (var row = 0; row <= rows; row++) {
      final v = source.top + source.height * row / rows;
      final start = reverse ? size.width - source.right : source.left;
      final end = reverse ? size.width - source.left : source.right;
      final edge = fold - (v - size.height / 2) * math.tan(tilt);
      for (var column = 0; column < columns; column++) {
        final u = column == 0
            ? start
            : column == columns - 1
                ? end
                : (edge +
                        radius *
                            math.pi *
                            (column - 1) /
                            segments /
                            math.cos(tilt))
                    .clamp(start, end);
        final point = project(Offset(u, v));
        positions.add(point.position);
        texture.add(Offset(reverse ? size.width - u : u, v));
        angles.add(point.angle);
      }
    }
    final indices = <int>[];
    final front = <int>[];
    final back = <int>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns - 1; column++) {
        final a = row * columns + column;
        final b = a + 1;
        final c = a + columns;
        final d = c + 1;
        for (final triangle in [
          <int>[a, b, c],
          <int>[b, d, c],
        ]) {
          indices.addAll(triangle);
          final angle =
              triangle.fold<double>(0, (sum, i) => sum + angles[i]) / 3;
          if (angle > math.pi / 2) {
            back.addAll(triangle);
          } else if (angle > 0) {
            front.addAll(triangle);
          }
        }
      }
    }
    return TextbookCurlMesh(
      positions: positions,
      texture: texture,
      angles: angles,
      indices: indices,
      front: front,
      back: back,
    );
  }
}

class TextbookCurlMesh {
  const TextbookCurlMesh({
    required this.positions,
    required this.texture,
    required this.angles,
    required this.indices,
    required this.front,
    required this.back,
  });

  final List<Offset> positions;
  final List<Offset> texture;
  final List<double> angles;
  final List<int> indices;
  final List<int> front;
  final List<int> back;
}
