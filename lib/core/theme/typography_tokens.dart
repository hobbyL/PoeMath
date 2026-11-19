// lib/core/theme/typography_tokens.dart
//
// 层级：core/theme（设计令牌 - 字体）
// 职责：字号阶梯、字重与两套主题的专用样式常量。
// 规则：新增字号必须落到这里，不允许 widget 内散写 fontSize: 18 之类的数值。
// 字体：标题与诗句使用随包文楷，说明、操作和算式使用系统字体。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';

/// 字体令牌汇总。
class TypographyTokens {
  const TypographyTokens._();

  /// 随包离线字体，不依赖设备是否预装中文衬线字族。
  static const String inkFontFamily = 'LXGWWenKaiLite';

  // ============ 字号阶梯（16 基线） ============
  static const double fsDisplay = 34.0;
  static const double fsHeadline = 26.0;
  static const double fsTitle = 20.0;

  /// 卡片内的小节标题（大于正文、小于卡片标题）。
  static const double fsSection = 18.0;
  static const double fsBody = 16.0;
  static const double fsBodySmall = 14.0;
  static const double fsCaption = 13.0;
  static const double fsLabel = 12.0;

  /// 行内状态标签，不用于正文或操作按钮标题。
  static const double fsCompactLabel = 11.0;

  // ============ 诗词专用（更大，儿童阅读舒适度） ============
  static const double fsPoemTitle = 28.0;

  /// 诗句正文（≥20，符合儿童阅读舒适度要求）
  static const double fsPoemContent = 24.0;
  static const double fsPinyin = 14.0;

  // ============ 口算专用 ============
  /// 口算大数字（低龄用户高识别）
  static const double fsMathProblem = 42.0;

  /// 缺字回退，主字族由随包文楷提供。
  static const List<String> serifFallback = [
    'Noto Serif SC',
    'Source Han Serif',
    'Songti SC', // macOS/iOS 预装的宋体
    'STSong', // iOS 备选
    'serif', // 通用 serif fallback
  ];

  /// 诗句正文样式（挂到 PoemThemeExt.poemContent）
  static TextStyle poemContentStyle({
    Color color = ColorTokens.poemInk,
    String? fontFamily = inkFontFamily,
  }) => TextStyle(
    fontSize: fsPoemContent,
    height: 1.8,
    letterSpacing: 2.0,
    color: color,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamily == null ? null : serifFallback,
  );

  /// 口算题目大数字样式（挂到 MathThemeExt.problemNumber）
  static TextStyle mathProblemStyle({Color color = ColorTokens.mathTextDark}) =>
      TextStyle(
        fontSize: fsMathProblem,
        fontWeight: FontWeight.w700,
        color: color,
      );
}
