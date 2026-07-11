// test/smoke_test.dart
//
// Phase 0 冒烟测试：确保 App 冷启动能展示 SplashPage，
// 并在 splash 定时结束后自动进入 MainShell + NotchedBottomBar。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/features/shell/main_shell.dart';
import 'package:poemath/features/shell/splash_page.dart';
import 'package:poemath/features/shell/widgets/notched_bottom_bar.dart';

void main() {
  testWidgets('App 冷启动应展示 SplashPage 并在 300ms 后进入 MainShell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    expect(find.byType(SplashPage), findsOneWidget);

    // splash 定时 300ms，pump 稍长以完成路由跳转与动画
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(NotchedBottomBar), findsOneWidget);
  });
}
