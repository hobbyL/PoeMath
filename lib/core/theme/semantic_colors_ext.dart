// lib/core/theme/semantic_colors_ext.dart
//
// 层级：core/theme
// 职责：跨主题语义色 ThemeExtension。
//       诗词/口算两套主题各自映射不同的 success / caution 颜色，
//       widget 层通过 `theme.semantic.success` 访问，无需关心当前主题。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';

/// 跨主题语义色 — 通过 [ThemeExtension] 机制跟随主题切换。
///
/// 使用：
/// ```dart
/// final theme = Theme.of(context);
/// color: theme.semantic.success,
/// ```
class SemanticColorsExt extends ThemeExtension<SemanticColorsExt> {
  const SemanticColorsExt({required this.success, required this.caution});

  /// 正确 / 成功 / 已解决。
  /// 按亮暗主题校准的信息前景，也可低透明度用于提示区域背景。
  final Color success;

  /// 中等 / 警告 / 装饰强调。
  /// 浅色主题使用深金色，深色主题使用明亮金色/奶油黄。
  final Color caution;

  @override
  SemanticColorsExt copyWith({Color? success, Color? caution}) {
    return SemanticColorsExt(
      success: success ?? this.success,
      caution: caution ?? this.caution,
    );
  }

  @override
  SemanticColorsExt lerp(ThemeExtension<SemanticColorsExt>? other, double t) {
    if (other is! SemanticColorsExt) return this;
    return SemanticColorsExt(
      success: Color.lerp(success, other.success, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
    );
  }
}

/// 便捷访问 — `theme.semantic.success` 代替冗长的 extension 调用。
///
/// 若 ThemeData 未注册 [SemanticColorsExt]（如测试中使用裸 MaterialApp），
/// 回退到诗词主题默认值，避免空指针。
extension ThemeDataSemanticX on ThemeData {
  SemanticColorsExt get semantic =>
      extension<SemanticColorsExt>() ??
      (brightness == Brightness.dark
          ? const SemanticColorsExt(
              success: ColorTokens.mathMint,
              caution: ColorTokens.poemGold,
            )
          : const SemanticColorsExt(
              success: ColorTokens.successText,
              caution: ColorTokens.cautionText,
            ));
}
