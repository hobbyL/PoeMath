// lib/features/math/widgets/math_text.dart
//
// 层级：features/math/widgets
// 职责：数学表达式文本组件 — 自动检测分数（如 1/3）并用 LaTeX 渲染，
//       否则降级为普通 Text。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 数学表达式文本组件。
///
/// 自动检测文本中的分数模式（如 `1/3`、`12/5`），
/// 当存在分数时使用 `flutter_math_fork` 的 `Math.tex()` 渲染 LaTeX，
/// 否则直接使用普通 [Text]。
class MathText extends StatelessWidget {
  const MathText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
  });

  /// 原始数学表达式文本，如 "1/3 + 2/5 = ?"。
  final String text;

  /// 文本样式。
  final TextStyle? style;

  /// 对齐方式（仅对纯文本生效；LaTeX 默认居中）。
  final TextAlign? textAlign;

  /// 匹配分数模式：前后为空格/运算符/行首尾的 `数字/数字`。
  ///
  /// 使用 lookbehind/lookahead 避免匹配日期等非分数格式。
  /// 例如匹配 `1/3`、`12/5`，不匹配 `2026/07/18`（三段斜杠）。
  static final _fractionPattern = RegExp(r'(?<!\d/)\b(\d+)/(\d+)\b(?!/\d)');

  /// 是否包含分数。
  bool get hasFraction => _fractionPattern.hasMatch(text);

  /// 将文本转换为 LaTeX 表达式。
  ///
  /// - 分数 `a/b` → `\frac{a}{b}`
  /// - 运算符和其他字符保持不变
  /// - `?` 保持不变（题目中的未知数占位）
  String get _latex {
    // 先替换运算符为 LaTeX 格式
    var result = text;

    // 替换分数
    result = result.replaceAllMapped(_fractionPattern, (m) {
      return '\\frac{${m.group(1)}}{${m.group(2)}}';
    });

    // 替换乘号和除号为 LaTeX 符号
    result = result.replaceAll('×', '\\times ');
    result = result.replaceAll('÷', '\\div ');

    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasFraction) {
      return Text(
        text,
        style: style,
        textAlign: textAlign ?? TextAlign.center,
      );
    }

    return Math.tex(
      _latex,
      textStyle: style,
      onErrorFallback: (_) => Text(
        text,
        style: style,
        textAlign: textAlign ?? TextAlign.center,
      ),
    );
  }
}
