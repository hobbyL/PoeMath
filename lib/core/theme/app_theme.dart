// lib/core/theme/app_theme.dart
//
// 层级：core/theme（主题 Facade）
// 职责：根据 (subject, brightness) 组合返回最终的 ThemeData。
//       作为 UI 层与 poem/math 具体主题实现之间的门面。
// 依赖：PoemTheme / MathTheme。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/math_theme.dart';
import 'package:poemath/core/theme/poem_theme.dart';

/// 当前活跃学科：决定加载哪一套主题。
enum AppSubject { poem, math }

/// 主题门面：外部只需调用 [AppTheme.resolve] 即可获得 ThemeData。
class AppTheme {
  const AppTheme._();

  /// 根据 [subject] 与 [brightness] 组合返回 ThemeData。
  static ThemeData resolve({
    required AppSubject subject,
    required Brightness brightness,
  }) {
    switch (subject) {
      case AppSubject.poem:
        return brightness == Brightness.light
            ? PoemTheme.light()
            : PoemTheme.dark();
      case AppSubject.math:
        return brightness == Brightness.light
            ? MathTheme.light()
            : MathTheme.dark();
    }
  }
}
