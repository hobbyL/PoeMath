// test/smoke_test.dart
//
// Phase 0 冒烟测试：确保 App 冷启动能展示 SplashPage，
// 并在 splash 定时结束后自动进入 MainShell + NotchedBottomBar。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/features/shell/main_shell.dart';
import 'package:poemath/features/shell/splash_page.dart';
import 'package:poemath/features/shell/widgets/notched_bottom_bar.dart';

import 'helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('App 冷启动应展示 SplashPage 并在 300ms 后进入 MainShell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    expect(find.byType(SplashPage), findsOneWidget);

    // DataBootstrap 版本匹配跳过导入 → 300ms 延迟 → 路由跳转
    // 用 pump 代替 pumpAndSettle（Lottie fallback 有永久动画）
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(NotchedBottomBar), findsOneWidget);

    // 消耗 MainShell IndexedStack 中所有 tab 页面的
    // flutter_animate 入场动画计时器
    await tester.pump(const Duration(seconds: 3));
  });
}
