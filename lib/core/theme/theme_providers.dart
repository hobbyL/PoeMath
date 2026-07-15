// lib/core/theme/theme_providers.dart
//
// 层级：core/theme（Riverpod Providers）
// 职责：暴露主题相关的可变状态和派生 ThemeData。
//       - activeSubjectProvider: 当前学科（poem / math），驱动主题切换。
//       - themeModeProvider: 亮色/暗色/跟随系统。
//       - lightThemeProvider / darkThemeProvider: 派生 ThemeData。

import 'dart:async' show Zone;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

/// 当前活跃学科 Notifier — 初始值从 Hive 读取，变更时自动写回。
///
/// 使用 [Zone.root] 调度 Hive 写入，避免 Flutter 测试中
/// FakeAsync zone 无法完成 I/O Future 导致测试超时。
class ActiveSubjectNotifier extends Notifier<AppSubject> {
  @override
  AppSubject build() {
    final stored =
        HiveBoxes.settings.get('active_subject', defaultValue: 'poem')
            as String;

    // 监听后续变更，自动持久化到 Hive
    listenSelf((prev, next) {
      if (prev != null && prev != next) {
        // 在根 Zone 中执行 I/O，避免 FakeAsync 追踪导致测试卡死
        Zone.root.run(() {
          HiveBoxes.settings.put(
            'active_subject',
            next == AppSubject.math ? 'math' : 'poem',
          );
        });
      }
    });

    return stored == 'math' ? AppSubject.math : AppSubject.poem;
  }

  /// 切换当前学科。
  void setSubject(AppSubject subject) {
    state = subject;
  }
}

/// 当前活跃学科（决定加载哪套主题）。
final activeSubjectProvider =
    NotifierProvider<ActiveSubjectNotifier, AppSubject>(
  ActiveSubjectNotifier.new,
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
