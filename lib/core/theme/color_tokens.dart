// lib/core/theme/color_tokens.dart
//
// 层级：core/theme（设计令牌 - 颜色板）
// 职责：集中定义诗词国风水墨 + 口算童趣马卡龙 + 语义色 + 深色映射的全部颜色常量。
// 规则：所有 widget 与主题构建器 **只能** 从此文件读取颜色，禁止在业务代码中硬编码 Color(0xFF...)。

import 'package:flutter/painting.dart';

/// 颜色令牌总入口。
///
/// 通过 `ColorTokens.poemGreen` / `ColorTokens.mathPurple` 访问。
class ColorTokens {
  const ColorTokens._();

  // ============ 诗词国风水墨 ============
  /// 宣纸底：Scaffold 背景
  static const Color poemPaper = Color(0xFFF9F7F2);

  /// 宣纸深：卡片/次级背景
  static const Color poemPaperDeep = Color(0xFFEFEAE0);

  /// 墨色：主要文字
  static const Color poemInk = Color(0xFF2B2B2B);

  /// 淡墨：次级文字
  static const Color poemInkLight = Color(0xFF6B6B6B);

  /// 墨绿：主色调
  static const Color poemGreen = Color(0xFF436444);

  /// 墨绿深：按下 / 强调
  static const Color poemGreenDeep = Color(0xFF2F4A31);

  /// 朱砂：点缀强调色
  static const Color poemCinnabar = Color(0xFFB35C5C);

  /// 描金：装饰线 / 徽章
  static const Color poemGold = Color(0xFFC9A56A);

  /// 印章红：勋章 / 收藏标记
  static const Color poemSeal = Color(0xFFA83E3E);

  /// 淡宣纸分割线
  static const Color poemDivider = Color(0xFFDCD5C6);

  // ============ 口算童趣马卡龙 ============
  /// 温白底：Scaffold 背景
  static const Color mathBackground = Color(0xFFFFFDF7);

  /// 纯白 Surface：卡片
  static const Color mathSurface = Color(0xFFFFFFFF);

  /// 薰衣草紫：主色
  static const Color mathPurple = Color(0xFFB5A0E8);

  /// 奶油黄：次要色 / 高亮
  static const Color mathYellow = Color(0xFFFFD98A);

  /// 樱花粉：装饰 / 女孩向
  static const Color mathPink = Color(0xFFFFB1C1);

  /// 冰川蓝：进度 / 信息
  static const Color mathBlue = Color(0xFF9FD3E8);

  /// 薄荷绿：答对
  static const Color mathMint = Color(0xFFA8E6C9);

  /// 珊瑚：答错 / 强调
  static const Color mathCoral = Color(0xFFFF9A8B);

  /// 口算主文字色
  static const Color mathTextDark = Color(0xFF33333A);

  /// 口算次级文字色
  static const Color mathTextLight = Color(0xFF7A7A85);

  // ============ 语义色（跨主题共享） ============
  static const Color success = Color(0xFF52C41A);
  static const Color warning = Color(0xFFFAAD14);
  static const Color error = Color(0xFFFF4D4F);
  static const Color info = Color(0xFF1890FF);

  // ============ 深色模式（占位映射） ============
  /// 深色背景
  static const Color darkBackground = Color(0xFF1A1A1F);

  /// 深色卡片 Surface
  static const Color darkSurface = Color(0xFF25252C);

  /// 深色主文字
  static const Color darkTextPrimary = Color(0xFFECECEC);
}
