// lib/core/widgets/auto_fit_text_lines.dart
//
// 层级：core/widgets（共享组件）
// 职责：多行文本统一字号自适应 —— 以最长行为基准计算缩放，
//       组内所有行共用同一字号，杜绝逐行独立缩放导致的字号不一。

import 'package:flutter/widgets.dart';

/// 多行文本统一字号自适应组件（只缩不放，带字号下限）。
///
/// 与 [AutoFitText] 的分工：
/// - [AutoFitText] 面向互不相关的单行，各行独立缩放，行间字号可能不同；
/// - 本组件面向同一首诗/同一段落的逐行展示：先测出最长行的固有宽度，
///   以它为基准计算统一缩放比，全部行共用该字号，保证视觉字号一致。
///
/// 缩放语义（与 [AutoFitText] 三段式对齐）：
///   1. 最长行原字号放得下 → 全部行原字号；
///   2. 放不下但等比缩放后字号 ≥ [minFontSize] → 全部行用缩放后字号，
///      单行渲染；
///   3. 缩到 [minFontSize] 仍放不下 → 全部行用 [minFontSize]，
///      放不下的行允许换行（居中多行）。
class AutoFitTextLines extends StatelessWidget {
  const AutoFitTextLines({
    super.key,
    required this.lines,
    required this.styleFor,
    required this.minFontSize,
    this.textAlign = TextAlign.center,
    this.lineWrapper,
    this.linePadding = EdgeInsets.zero,
  });

  /// 逐行文本（调用方已按行拆分）。
  final List<String> lines;

  /// 每行渲染样式（fontSize 为基准字号）；行间可差异（如朗读高亮行），
  /// 但缩放决策按各行的实际样式测宽，保证高亮行也不溢出。
  final TextStyle Function(int index) styleFor;

  /// 字号下限：统一缩放到该字号仍放不下时改为换行展示。
  final double minFontSize;

  /// 文本对齐方式，默认居中（换行时各行也居中）。
  final TextAlign textAlign;

  /// 可选的逐行包装（如朗读高亮背景）；返回值直接替代该行渲染。
  ///
  /// 注意：包装不得自带水平 padding，否则文字测宽（按组件总宽）与
  /// 渲染（扣除 padding）不一致，行尾会被裁切；行内边距请用 [linePadding]。
  final Widget Function(int index, Widget line)? lineWrapper;

  /// 每行文字的内边距；测宽时从可用宽度中扣除，保证渲染不溢出。
  final EdgeInsets linePadding;

  @override
  Widget build(BuildContext context) {
    final textDirection =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;

    TextStyle resolveStyle(TextStyle style) => style.inherit
        ? DefaultTextStyle.of(context).style.merge(style)
        : style;

    final baseStyle = resolveStyle(styleFor(0));
    final baseFontSize = baseStyle.fontSize;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth - linePadding.horizontal;
        // 无界宽度或无字号：无法计算缩放比例，按原样式渲染（允许换行）。
        if (!maxWidth.isFinite || baseFontSize == null) {
          return _buildLines(resolveStyle, (_) => baseStyle, false);
        }
        // 防御：下限不低于原字号时，退化为「原字号换行」。
        if (minFontSize >= baseFontSize) {
          return _buildLines(resolveStyle, (_) => baseStyle, false);
        }

        // 以最长行（按各自行样式测宽）为基准求统一缩放比。
        var maxIntrinsicWidth = 0.0;
        for (var i = 0; i < lines.length; i++) {
          final width = measureSingleLineWidth(
            lines[i],
            resolveStyle(styleFor(i)),
            textDirection,
            textScaler,
          );
          if (width > maxIntrinsicWidth) maxIntrinsicWidth = width;
        }

        // 1. 最长行放得下：全部原字号，不缩不放。
        if (maxIntrinsicWidth <= maxWidth) {
          return _buildLines(resolveStyle, (_) => baseStyle, true);
        }

        final scale = (maxWidth / maxIntrinsicWidth).clamp(0.0, 1.0);
        final scaledFontSize = baseFontSize * scale;

        // 3. 缩到下限仍放不下：全部用 minFontSize，放不下的行换行。
        if (scaledFontSize < minFontSize) {
          return _buildLines(
            resolveStyle,
            (style) => scaled(style, minFontSize, baseFontSize),
            false,
          );
        }

        // 2. 全部行用统一缩放字号，单行渲染（softWrap 关闭防亚像素换行）。
        return _buildLines(
          resolveStyle,
          (style) => scaled(style, scaledFontSize, baseFontSize),
          true,
        );
      },
    );
  }

  /// 按统一比例缩放字号与 letterSpacing，保持行内视觉比例。
  TextStyle scaled(TextStyle style, double fontSize, double baseFontSize) {
    final letterSpacing = style.letterSpacing ?? 0.0;
    return style.copyWith(
      fontSize: fontSize,
      letterSpacing: letterSpacing * (fontSize / baseFontSize),
    );
  }

  Widget _buildLines(
    TextStyle Function(TextStyle) resolveStyle,
    TextStyle Function(TextStyle) transform,
    bool singleLine,
  ) {
    return Column(
      children: [
        for (var i = 0; i < lines.length; i++)
          _wrap(
            i,
            Padding(
              padding: linePadding,
              child: Text(
                lines[i],
                style: transform(resolveStyle(styleFor(i))),
                textAlign: textAlign,
                maxLines: singleLine ? 1 : null,
                softWrap: !singleLine,
              ),
            ),
          ),
      ],
    );
  }

  Widget _wrap(int index, Widget line) {
    final wrapper = lineWrapper;
    return wrapper == null ? line : wrapper(index, line);
  }
}

/// 用 TextPainter 测量单行固有宽度（无宽度约束下的自然宽度）。
double measureSingleLineWidth(
  String text,
  TextStyle style,
  TextDirection textDirection,
  TextScaler textScaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout();
  try {
    return painter.width;
  } finally {
    painter.dispose();
  }
}
