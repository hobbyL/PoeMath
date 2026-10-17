import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/features/math/math_tab_page.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/practice_scheme_selector.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final sample in [
    (1, '上', DifficultyLevel.medium, false),
    (5, '下', DifficultyLevel.medium, false),
    (2, '上', DifficultyLevel.easy, false),
    (2, '上', DifficultyLevel.medium, true),
  ]) {
    testWidgets('$sample 隐藏不支持的竖式方案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeSchemeSelector(
              grade: sample.$1,
              semester: sample.$2,
              difficulty: sample.$3,
              vertical: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(
        find.widgetWithText(ChoiceChip, '竖式'),
        sample.$4 ? findsOneWidget : findsNothing,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '普通'))
            .selected,
        !sample.$4,
      );
    });
  }

  for (final vertical in [false, true]) {
    testWidgets(
        '卡片直接进入${vertical ? '竖式' : '普通口算'}练习：沿用当前册次题量且不改偏好',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await HiveBoxes.settings.put('math_batch_size', 10);
        await HiveBoxes.settings.put('math_difficulty', 'medium');
        // 偏好指向竖式 —— 验证口算卡片不照办（回落综合），竖式卡片照办。
        await HiveBoxes.settings.put('math_practice_mode', 'vertical');
        // 册次只能经学习背景写入（口算页的就地选择已移除），故此处直接
        // 落 Hive —— 保证它在下面的 `before` 快照内，配得出「练习不写盘」。
        await HiveBoxes.settings.put('selected_grade', 2);
        await HiveBoxes.settings.put('selected_semester', '上');
      });
      final before = HiveBoxes.settings.toMap();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const MathTabPage()),
          GoRoute(
            path: AppRoutes.mathPractice,
            builder: (_, __) => const MathPracticePage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      // 方案选择弹窗已移除：竖式是独立卡片，点哪张卡片即选定方案。
      expect(find.text('练习方案'), findsNothing);
      await tester.tap(find.text(vertical ? '竖式计算' : '口算练习'));
      // 点击后路由 push + 练习页挂载 + 入场动画（flutter_animate 的
      // Timer 须推进完，否则测试结束时报 timersPending）。用显式 pump
      // 而非 pumpAndSettle（见 spec「Widget Tests with Focus and
      // Animations」）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      final problems = container.read(mathProblemsProvider);
      expect(problems, hasLength(10));
      expect(problems.every((p) => p.grade == 2 && p.semester == '上'), isTrue);
      expect(
        problems.every((p) => (p.mode == ProblemMode.vertical) == vertical),
        isTrue,
      );
      // 练习不改写任何偏好（含 math_practice_mode —— 即便口算卡片因偏好
      // 指向竖式而回落综合，也只是本次请求的 mode，不回写偏好）。
      expect(container.read(mathPracticeModeProvider), ProblemMode.vertical);
      expect(HiveBoxes.settings.toMap(), before);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      // 排空残余动画计时器（卡片 500ms 级联入场）。
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
