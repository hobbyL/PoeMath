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
  const SemanticColorsExt({
    required this.success,
    required this.caution,
  });

  /// 正确 / 成功 / 已解决。
  /// 诗词：翠绿 (0xFF52C41A)，口算：薄荷绿 (0xFFA8E6C9)。
  final Color success;

  /// 中等 / 警告 / 装饰强调。
  /// 诗词：描金 (0xFFC9A56A)，口算：奶油黄 (0xFFFFD98A)。
  final Color caution;

  @override
  SemanticColorsExt copyWith({Color? success, Color? caution}) {
    return SemanticColorsExt(
      success: success ?? this.success,
      caution: caution ?? this.caution,
    );
  }

  @override
  SemanticColorsExt lerp(
    ThemeExtension<SemanticColorsExt>? other,
    double t,
  ) {
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
  static const _fallback = SemanticColorsExt(
    success: ColorTokens.success,
    caution: ColorTokens.poemGold,
  );

  SemanticColorsExt get semantic =>
      extension<SemanticColorsExt>() ?? _fallback;
}
