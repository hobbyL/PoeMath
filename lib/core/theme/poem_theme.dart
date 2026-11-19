import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/ink_theme.dart';
import 'package:poemath/core/theme/typography_tokens.dart';

/// 宣纸·松墨；保留既有主题入口和偏好存储值。
class PoemTheme {
  const PoemTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final theme = InkTheme.build(brightness: brightness, ochre: false);
    return theme.copyWith(
      extensions: [
        ...theme.extensions.values,
        PoemThemeExt(
          contentColor: theme.colorScheme.onSurface,
          pinyinColor: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// 挂在 ThemeData 上的诗词专属样式扩展。
///
/// 使用：`Theme.of(context).extension<PoemThemeExt>()!.poemContent`
class PoemThemeExt extends ThemeExtension<PoemThemeExt> {
  const PoemThemeExt({
    this.contentColor = ColorTokens.poemInk,
    this.pinyinColor = ColorTokens.poemInkLight,
  });

  final Color contentColor;
  final Color pinyinColor;

  TextStyle get poemContent =>
      TypographyTokens.poemContentStyle(color: contentColor);

  TextStyle get pinyin =>
      TextStyle(fontSize: TypographyTokens.fsPinyin, color: pinyinColor);

  @override
  PoemThemeExt copyWith({Color? contentColor, Color? pinyinColor}) =>
      PoemThemeExt(
        contentColor: contentColor ?? this.contentColor,
        pinyinColor: pinyinColor ?? this.pinyinColor,
      );

  @override
  PoemThemeExt lerp(ThemeExtension<PoemThemeExt>? other, double t) {
    if (other is! PoemThemeExt) return this;
    return PoemThemeExt(
      contentColor: Color.lerp(contentColor, other.contentColor, t)!,
      pinyinColor: Color.lerp(pinyinColor, other.pinyinColor, t)!,
    );
  }
}
