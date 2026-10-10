// lib/features/assistant/widgets/assistant_markdown.dart
//
// 层级：features/assistant/widgets
// 职责：助手消息的 Markdown + LaTeX 渲染组件。
//       基于 gpt_markdown 渲染正文（标题/列表/代码/表格等），
//       数学公式（$...$ / $$...$$）委托 flutter_math_fork 的 Math.tex
//       渲染，保持与全 App 数学排版一致（见 design §1.1）。
//       流式阶段用 fade 动画逐段淡入；非流式静态渲染。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// 助手消息 Markdown 渲染组件。
///
/// - [text]：Markdown 原文（可含 `$...$` 行内公式、`$$...$$` 块级公式）。
/// - [isStreaming]：是否仍在流式接收。为 true 时启用 fade 逐段淡入动画。
/// - [style]：正文基础样式；为空时沿用主题 bodyMedium。
class AssistantMarkdown extends StatelessWidget {
  const AssistantMarkdown(
    this.text, {
    super.key,
    this.isStreaming = false,
    this.style,
  });

  /// Markdown 原文。
  final String text;

  /// 是否流式接收中（启用 fade 动画）。
  final bool isStreaming;

  /// 正文基础样式。
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium;

    return SelectionArea(
      child: GptMarkdown(
        text,
        style: baseStyle,
        isStreaming: isStreaming,
        animation: isStreaming
            ? GptMarkdownAnimation.fade
            : GptMarkdownAnimation.none,
        useDollarSignsForLatex: true,
        // 行内公式：委托 flutter_math_fork，解析失败回退原文。
        inlineLatexBuilder: (d) => d.asWidgetSpan(
          Math.tex(
            d.tex,
            textStyle: d.style,
            onErrorFallback: (_) => Text(d.source, style: d.style),
          ),
        ),
        // 块级公式：同样委托 flutter_math_fork。
        blockLatexBuilder: (d) => Math.tex(
          d.tex,
          textStyle: d.style,
          onErrorFallback: (_) => Text(d.source, style: d.style),
        ),
      ),
    );
  }
}
