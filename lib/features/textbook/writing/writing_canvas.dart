import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:poemath/features/textbook/writing/writing_path.dart';

typedef CanvasPoint = math.Point<double>;

/// 田字格专用画笔组件：米字辅助线 + 可选参考字形 + 可选描红底图 + 手写轨迹。
///
/// 只负责绘制；手势捕获在 [WritingCanvas] 中完成。
class TianziGridPainter extends CustomPainter {
  TianziGridPainter({
    required this.gridColor,
    this.referenceStrokes,
    this.traceOpacity = 0,
    this.userStrokes = const [],
    this.highlightStroke,
    this.strokeColor = Colors.black,
    this.strokeWidth = 3,
    this.showCharacter,
    this.strokeScale = 1,
  }) : super(repaint: null);

  final Color gridColor;

  /// 参考字形轮廓（SVG path 字符串）；为空时只画格。
  final List<String>? referenceStrokes;

  /// 参考字形透明度（描红底图用，0 = 不画）。
  final double traceOpacity;

  /// 孩子笔迹（格内局部坐标）。
  final List<List<Offset>> userStrokes;

  /// 高亮笔号（核对阶段标出首错笔画）。
  final int? highlightStroke;
  final Color strokeColor;
  final double strokeWidth;

  /// 无笔顺数据时的降级显示（直接绘制字符，AC6）。
  final String? showCharacter;

  /// 笔迹坐标缩放比（预览尺寸 / 记录尺寸）。
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (showCharacter case final char?) {
      _paintCharacterFallback(canvas, size, char);
    }
    if (referenceStrokes case final strokes? when traceOpacity > 0) {
      _paintReference(canvas, size, strokes, traceOpacity);
    }
    _paintUserStrokes(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, paint);

    final dashed = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // 十字线。
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      dashed,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      dashed,
    );
    // 米字斜线。
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), dashed);
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(0, size.height),
      dashed,
    );
  }

  void _paintReference(
    Canvas canvas,
    Size size,
    List<String> strokes,
    double opacity,
  ) {
    final side = math.min(size.width, size.height);
    canvas.save();
    canvas.transform(hanziCanvasMatrix(side));
    final paint = Paint()
      ..color = strokeColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(characterOutline(strokes), paint);
    canvas.restore();
  }

  void _paintCharacterFallback(Canvas canvas, Size size, String character) {
    final painter = TextPainter(
      text: TextSpan(
        text: character,
        style: TextStyle(
          fontSize: size.shortestSide * 0.72,
          color: strokeColor.withValues(alpha: 0.22),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
    painter.dispose();
  }

  void _paintUserStrokes(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = strokeWidth * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final highlight = Paint()
      ..color = const Color(0xFFB35C5C)
      ..strokeWidth = (strokeWidth + 1) * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < userStrokes.length; i++) {
      final stroke = userStrokes[i];
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * strokeScale, stroke.first.dy * strokeScale);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * strokeScale, point.dy * strokeScale);
      }
      canvas.drawPath(path, i == highlightStroke ? highlight : paint);
    }
  }

  @override
  bool shouldRepaint(TianziGridPainter old) =>
      old.gridColor != gridColor ||
      old.referenceStrokes != referenceStrokes ||
      old.traceOpacity != traceOpacity ||
      old.userStrokes != userStrokes ||
      old.highlightStroke != highlightStroke ||
      old.strokeColor != strokeColor ||
      old.strokeWidth != strokeWidth ||
      old.showCharacter != showCharacter ||
      old.strokeScale != strokeScale;
}

/// 手写捕获画布：田字格 + 手势。
///
/// 只收集笔画；撤销/清空由父组件通过 [strokes] 控制（受控组件）。
class WritingCanvas extends StatefulWidget {
  const WritingCanvas({
    super.key,
    required this.strokes,
    this.onStrokesChanged,
    this.referenceStrokes,
    this.traceOpacity = 0,
    this.highlightStroke,
    this.showCharacter,
    this.strokesSide,
    this.side = 240,
    this.enabled = true,
  });

  final List<List<Offset>> strokes;
  final ValueChanged<List<List<Offset>>>? onStrokesChanged;
  final List<String>? referenceStrokes;
  final double traceOpacity;
  final int? highlightStroke;
  final String? showCharacter;

  /// [strokes] 记录时使用的画布边长。
  ///
  /// 核对阶段用小尺寸预览「我写的」，但坐标是按书写时的画布尺寸记录的；
  /// 传入该尺寸后按比例缩放绘制，否则笔迹只出现在右下角一小块。
  final double? strokesSide;
  final double side;
  final bool enabled;

  @override
  State<WritingCanvas> createState() => _WritingCanvasState();
}

class _WritingCanvasState extends State<WritingCanvas> {
  /// 进行中的一笔。只在本组件内绘制，收笔时才并入 [WritingCanvas.strokes]。
  ///
  /// 若在每次移动时就把"已写部分"回传给父组件，父组件会把它当成新的一笔
  /// 追加，几秒书写就会累积出上百笔（实测 7 笔 → 116 笔）。
  List<Offset>? _active;

  /// 抢占指针的识别器：按下即赢，避免田字格被外层 `ListView` 的滚动手势抢走。
  final _eager = EagerGestureRecognizer();

  @override
  void dispose() {
    _eager.dispose();
    super.dispose();
  }

  /// 绘制用笔画：已完成的 + 进行中的一笔。
  List<List<Offset>> get _painting => [
        ...widget.strokes,
        if (_active != null && _active!.isNotEmpty) _active!,
      ];

  void _start(Offset local) {
    setState(() => _active = [local]);
  }

  void _move(Offset local) {
    final active = _active;
    if (active == null) return;
    setState(() => active.add(local));
  }

  /// 收笔：把这一笔并入已完成笔画后回传父组件。
  void _finish() {
    final active = _active;
    setState(() => _active = null);
    if (active == null || active.isEmpty) return;
    widget.onStrokesChanged?.call([
      for (final stroke in widget.strokes) List<Offset>.of(stroke),
      List<Offset>.of(active),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strokes = _painting;
    final canvas = SizedBox.square(
      dimension: widget.side,
      child: ClipRect(
        child: CustomPaint(
          key: const ValueKey('writing-canvas'),
          painter: TianziGridPainter(
            gridColor: theme.colorScheme.outline,
            referenceStrokes: widget.referenceStrokes,
            traceOpacity: widget.traceOpacity,
            userStrokes: strokes,
            highlightStroke: widget.highlightStroke,
            strokeColor: theme.colorScheme.onSurface,
            showCharacter: widget.showCharacter,
            strokeScale: widget.strokesSide == null
                ? 1
                : widget.side / widget.strokesSide!,
          ),
          size: Size.square(widget.side),
        ),
      ),
    );
    if (!widget.enabled) return canvas;
    // 用 Eager 手势识别器抢占 arena：田字格在 ListView 内，若用普通
    // GestureDetector，竖/斜向的笔画会被列表的滚动手势抢走（汉字几乎全是
    // 竖笔），表现为"写了没反应"。Eager 在指针按下即宣告胜利，滚动让位。
    final recognizer = _eager;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => recognizer,
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _start(event.localPosition),
        onPointerMove: (event) => _move(event.localPosition),
        onPointerUp: (_) => _finish(),
        onPointerCancel: (_) => _finish(),
        child: canvas,
      ),
    );
  }
}

/// 总览字卡用的小田字格（只显示参考字形或降级字符，禁止交互）。
class MiniTianziGrid extends StatelessWidget {
  const MiniTianziGrid({
    super.key,
    this.referenceStrokes,
    this.character,
    this.side = 88,
  });

  final List<String>? referenceStrokes;
  final String? character;
  final double side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: TianziGridPainter(
          gridColor: theme.colorScheme.outline.withValues(alpha: 0.6),
          referenceStrokes: referenceStrokes,
          traceOpacity: referenceStrokes == null ? 0 : 0.88,
          showCharacter: referenceStrokes == null ? character : null,
          strokeColor: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 逐笔动画绘制器：按进度揭示参考笔画的填充。
///
/// 用轮廓裁剪实现"写到一半"的效果：第 [revealed] 笔之前全部显示，当前笔按
/// [progress] 以圆形裁剪从起笔处向外扩展，之后不显示。
class StrokeRevealPainter extends CustomPainter {
  StrokeRevealPainter({
    required this.strokes,
    required this.medians,
    required this.revealed,
    required this.progress,
    required this.color,
    required this.gridColor,
    required this.side,
  });

  final List<String> strokes;
  final List<List<CanvasPoint>> medians;
  final int revealed;
  final double progress;
  final Color color;
  final Color gridColor;
  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = TianziGridPainter(gridColor: gridColor);
    grid.paint(canvas, size);

    final matrix = hanziCanvasMatrix(size.shortestSide);
    canvas.save();
    canvas.transform(matrix);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final count = revealed.clamp(0, strokes.length);
    for (var i = 0; i < count; i++) {
      canvas.drawPath(parseSvgPath(strokes[i]), fill);
    }
    if (count < strokes.length && progress > 0) {
      // 当前笔：用从起笔处扩展的圆裁剪轮廓。
      final current = medians[count];
      if (current.isNotEmpty) {
        final start = current.first;
        var radius = 0.0;
        for (final point in current) {
          radius = math.max(
            radius,
            math.sqrt(
              math.pow(point.x - start.x, 2) + math.pow(point.y - start.y, 2),
            ),
          );
        }
        radius *= progress.clamp(0.0, 1.0);
        canvas.save();
        canvas.clipPath(
          Path()
            ..addOval(
              Rect.fromCircle(
                center: Offset(start.x, start.y),
                radius: math.max(radius, 1),
              ),
            ),
        );
        canvas.drawPath(parseSvgPath(strokes[count]), fill);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StrokeRevealPainter old) =>
      old.revealed != revealed ||
      old.progress != progress ||
      old.strokes != strokes ||
      old.color != color ||
      old.side != side;
}