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
    testWidgets('开始${vertical ? '竖式' : '普通'}练习沿用当前册次题量且不改偏好', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await HiveBoxes.settings.put('math_batch_size', 10);
        await HiveBoxes.settings.put('math_difficulty', 'medium');
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
      expect(find.text('竖式过程练'), findsNothing);
      // 口算入口已由底部按钮改为一级卡片。
      await tester.tap(find.text('口算'));
      await tester.pumpAndSettle();
      expect(find.text('练习方案'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, vertical ? '竖式' : '普通'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('开始练习'));
        await tester.pump();
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
      expect(container.read(mathGradeProvider), 2);
      expect(container.read(mathSemesterProvider), '上');
      expect(container.read(mathPracticeModeProvider), ProblemMode.vertical);
      expect(HiveBoxes.settings.toMap(), before);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
    });
  }
}
