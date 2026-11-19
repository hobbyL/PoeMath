// lib/core/theme/app_theme.dart
//
// 层级：core/theme（主题 Facade）
// 职责：根据 (subject, brightness) 组合返回最终的 ThemeData。
//       作为 UI 层与 poem/math 具体主题实现之间的门面。
// 依赖：PoemTheme / MathTheme。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/math_theme.dart';
import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/core/theme/playful_theme.dart';
import 'package:poemath/domain/app_subject.dart';

export 'package:poemath/domain/app_subject.dart';

/// 主题门面：外部只需调用 [AppTheme.resolve] 即可获得 ThemeData。
class AppTheme {
  const AppTheme._();

  /// 根据 [subject] 与 [brightness] 组合返回 ThemeData。
  static ThemeData resolve({
    required AppSubject subject,
    required Brightness brightness,
  }) {
    return switch (subject) {
      AppSubject.poem =>
        brightness == Brightness.light ? PoemTheme.light() : PoemTheme.dark(),
      AppSubject.math =>
        brightness == Brightness.light ? MathTheme.light() : MathTheme.dark(),
      AppSubject.candy => PlayfulTheme.build(
        brightness: brightness,
        space: false,
      ),
      AppSubject.space => PlayfulTheme.build(
        brightness: brightness,
        space: true,
      ),
    };
  }
}
