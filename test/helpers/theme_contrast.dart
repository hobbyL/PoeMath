import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 先合成透明前景，再计算实际颜色配对的 WCAG 对比度。
double contrastRatio(Color foreground, Color background) {
  final front = Color.alphaBlend(foreground, background).computeLuminance();
  final back = background.computeLuminance();
  return (math.max(front, back) + .05) / (math.min(front, back) + .05);
}

/// 用于页面普通实色/半透明卡片；图片和渐变由各自的像素测试验证。
Color solidBackgroundOf(Element element) {
  final colors = <Color>[];
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    switch (widget) {
      case DecoratedBox(decoration: final BoxDecoration decoration):
        if (decoration.color case final color?) colors.add(color);
      case ColoredBox(:final color):
        colors.add(color);
      case Material(:final color?):
        colors.add(color);
    }
    return true;
  });
  return colors.reversed.fold(
    Theme.of(element).scaffoldBackgroundColor,
    (background, foreground) => Color.alphaBlend(foreground, background),
  );
}

void expectReadableText(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final text = element.widget as Text;
    final foreground = DefaultTextStyle.of(element).style
        .merge(text.style)
        .color!;
    expect(
      contrastRatio(foreground, solidBackgroundOf(element)),
      greaterThanOrEqualTo(4.5),
      reason: text.data ?? text.textSpan?.toPlainText(),
    );
  }
}

void expectReadableIcon(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final icon = element.widget as Icon;
    final foreground = icon.color ?? IconTheme.of(element).color!;
    expect(
      contrastRatio(foreground, solidBackgroundOf(element)),
      greaterThanOrEqualTo(3),
      reason: icon.icon.toString(),
    );
  }
}
