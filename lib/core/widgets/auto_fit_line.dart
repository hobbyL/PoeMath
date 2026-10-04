// lib/core/widgets/auto_fit_line.dart
//
// 层级：core/widgets（共享组件）
// 职责：让单行内容在宽度不足时整行等比缩小，宽度充足时保持原尺寸。

import 'package:flutter/widgets.dart';

/// 单行内容自适应容器（只缩不放）。
///
/// 宽度不足时把子内容等比缩小（字号、行高同比例，不换行）；
/// 宽度充足时保持子内容原始尺寸，绝不放大。
///
/// 子内容应按「单行固有宽度」参与布局：在本组件的无宽度约束下
/// `Wrap`/`RichText` 自然排成一行；`Text` 建议显式 `maxLines: 1`
/// 以表达意图。典型用途：诗词逐行展示，保证一句一行。
class AutoFitLine extends StatelessWidget {
  const AutoFitLine({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: child,
    );
  }
}
