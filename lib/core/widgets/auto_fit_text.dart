// lib/core/widgets/auto_fit_text.dart
//
// 层级：core/widgets（共享组件）
// 职责：文本专用单行自适应（只缩不放），缩到字号下限仍放不下时允许换行。

import 'package:flutter/widgets.dart';

/// 文本单行自适应组件（只缩不放，带字号下限）。
///
/// 与 [AutoFitLine] 的分工：
/// - [AutoFitLine] 面向任意 child，用 FittedBox 做几何缩放，无字号下限、
///   永不换行，适合跟读/背诵等逐字交互行（填字槽布局不允许换行）。
/// - 本组件面向纯文本，三段语义：
///   1. 单行固有宽度放得下 → 原字号单行（不缩不放）；
///   2. 放不下但等比缩放后字号 ≥ [minFontSize] → 字号与 letterSpacing
///      同比例缩小后仍单行渲染（视觉与 FittedBox.scaleDown 一致）；
///   3. 缩到 [minFontSize] 仍放不下 → 以 [minFontSize] 渲染并允许换行
///      （居中多行），保证长句字号下限可读。
///
/// [minFontSize] 由调用方从 Theme 取实际字号传入（如 bodyMedium），
/// 组件不硬编码；若传入值 ≥ 原字号，行为退化为「原字号换行」。
class AutoFitText extends StatelessWidget {
  const AutoFitText({
    super.key,
    required this.text,
    required this.style,
    required this.minFontSize,
    this.textAlign = TextAlign.center,
  });

  /// 待渲染文本（约定为单行内容，调用方已按行拆分）。
  final String text;

  /// 基础文本样式（fontSize 为原始字号）。
  final TextStyle style;

  /// 字号下限：等比缩放到该字号仍放不下时改为换行展示。
  final double minFontSize;

  /// 文本对齐方式，默认居中（换行时各行也居中）。
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    // 与 Text 组件的合成规则保持一致：可继承样式先并入 DefaultTextStyle
    // （无环境样式时 of 返回全空的 fallback，merge 结果仍是原样式），
    // 保证 TextPainter 测宽与最终渲染使用同一份样式，宽度判定不漂移。
    var effectiveStyle = style;
    if (style.inherit) {
      effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    }
    final textDirection =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final baseFontSize = effectiveStyle.fontSize;
        // 无界宽度或无字号：无法计算缩放比例，按原样式渲染。
        if (!maxWidth.isFinite || baseFontSize == null) {
          return Text(text, style: effectiveStyle, textAlign: textAlign);
        }
        // 防御：下限不低于原字号时，退化为「原字号换行」。
        if (minFontSize >= baseFontSize) {
          return Text(text, style: effectiveStyle, textAlign: textAlign);
        }

        final intrinsicWidth = _measureSingleLineWidth(
          effectiveStyle,
          textDirection,
          textScaler,
        );

        // 1. 放得下：原字号单行，不缩不放。
        if (intrinsicWidth <= maxWidth) {
          return Text(
            text,
            style: effectiveStyle,
            textAlign: textAlign,
            maxLines: 1,
          );
        }

        final scale = (maxWidth / intrinsicWidth).clamp(0.0, 1.0).toDouble();
        final scaledFontSize = baseFontSize * scale;
        final letterSpacing = effectiveStyle.letterSpacing ?? 0.0;

        // 3. 缩到下限仍放不下：minFontSize 渲染并允许换行（居中多行）。
        if (scaledFontSize < minFontSize) {
          return Text(
            text,
            style: effectiveStyle.copyWith(
              fontSize: minFontSize,
              letterSpacing: letterSpacing * (minFontSize / baseFontSize),
            ),
            textAlign: textAlign,
          );
        }

        // 2. 等比缩放（字号与 letterSpacing 同比例）后仍单行；
        //    softWrap 关闭以结构性保证单行，杜绝测宽与渲染的亚像素误差换行。
        return Text(
          text,
          style: effectiveStyle.copyWith(
            fontSize: scaledFontSize,
            letterSpacing: letterSpacing * scale,
          ),
          textAlign: textAlign,
          maxLines: 1,
          softWrap: false,
        );
      },
    );
  }

  /// 用 TextPainter 测量单行固有宽度（无宽度约束下的自然宽度）。
  double _measureSingleLineWidth(
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
}
