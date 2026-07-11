// lib/core/theme/theme_providers.dart
//
// 层级：core/theme（Riverpod Providers）
// 职责：暴露主题相关的可变状态和派生 ThemeData。
//       - activeSubjectProvider: 当前学科（poem / math），驱动主题切换。
//       - themeModeProvider: 亮色/暗色/跟随系统。
//       - lightThemeProvider / darkThemeProvider: 派生 ThemeData。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/app_theme.dart';

/// 当前活跃学科（决定加载哪套主题）。默认诗词国风。
final activeSubjectProvider = StateProvider<AppSubject>(
  (ref) => AppSubject.poem,
);

/// 亮色 / 暗色 / 跟随系统。默认跟随系统。
final themeModeProvider = StateProvider<ThemeMode>(
  (ref) => ThemeMode.system,
);

/// 派生 Provider：根据当前 subject 返回亮色 ThemeData。
final lightThemeProvider = Provider<ThemeData>((ref) {
  final subject = ref.watch(activeSubjectProvider);
  return AppTheme.resolve(subject: subject, brightness: Brightness.light);
});

/// 派生 Provider：根据当前 subject 返回暗色 ThemeData。
final darkThemeProvider = Provider<ThemeData>((ref) {
  final subject = ref.watch(activeSubjectProvider);
  return AppTheme.resolve(subject: subject, brightness: Brightness.dark);
});
