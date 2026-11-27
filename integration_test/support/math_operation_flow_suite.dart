import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/math/math_tab_page.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/profile/practice_settings_page.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../test/helpers/hive_test_helper.dart'
    show drainHiveWritesForTesting;

Future<void> waitForOperationState(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(ready(), isTrue, reason: '等待界面或存储完成');
}

Future<void> _waitForNext(WidgetTester tester) =>
    waitForOperationState(tester, () {
      final next = find.byKey(const ValueKey('math-next-problem-button'));
      return next.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(next).onPressed != null;
    });

void defineMathOperationFlowTests({
  required Future<void> Function() setUpStorage,
  required Future<void> Function() tearDownStorage,
  Future<void> Function(WidgetTester tester, String name)? capture,
}) {
  setUp(setUpStorage);
  tearDown(tearDownStorage);

  testWidgets('次数设置到真实口算、作答、续练和结算完整往返', (tester) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final settings = SettingsRepository();
      await settings.setLearningBackground(3, '下');
      await settings.setSoundEnabled(false);
      await settings.setHapticEnabled(false);
    });
    final container = ProviderContainer();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const MathTabPage()),
        GoRoute(
          path: '/operation-settings',
          builder: (_, __) => const PracticeSettingsPage(),
        ),
        GoRoute(
          path: AppRoutes.mathPractice,
          builder: (_, state) => MathPracticePage(
            resume: state.uri.queryParameters['resume'] == '1',
          ),
        ),
      ],
    );
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: const ValueKey('operation-review-surface'),
            child: MaterialApp.router(
              theme: AppTheme.resolve(
                subject: AppSubject.poem,
                brightness: Brightness.light,
              ),
              routerConfig: router,
              builder: (_, child) =>
                  PageAnimationScope(enabled: false, child: child!),
            ),
          ),
        ),
      );
      router.push('/operation-settings');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '2 次'));
      await tester.tap(find.widgetWithText(FilterChip, '3 次'));
      await tester.tap(find.widgetWithText(ChoiceChip, '5 题'));
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '带括号'));
      await tester.tap(find.widgetWithText(ChoiceChip, '带括号'));
      await tester.pump();
      if (capture != null) {
        await tester.scrollUntilVisible(
          find.widgetWithText(FilterChip, '3 次'),
          -200,
        );
        await capture(tester, 'settings');
      }
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '保存'),
        300,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, '保存')),
      );
      await waitForOperationState(
        tester,
        () => find.byType(PracticeSettingsPage).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
      expect(SettingsRepository().mathOperationCounts?.values, [2, 3]);
      expect(find.text('2、3 次运算'), findsOneWidget);
      if (capture != null) await capture(tester, 'entry');

      await tester.tap(find.text('口算练习'));
      await waitForOperationState(
        tester,
        () => container.read(mathProblemsProvider).length == 5,
      );
      await tester.pump(const Duration(seconds: 1));
      final original = container
          .read(mathProblemsProvider)
          .map((p) => p.toJson())
          .toList();
      final generated = container.read(mathProblemsProvider);
      final twoCount = generated.where((p) => p.operators.length == 2).length;
      expect(twoCount, isIn([2, 3]));
      expect(
        generated.every((p) => p.mode == ProblemMode.withBrackets),
        isTrue,
      );
      if (capture != null) await capture(tester, 'question');

      // 通过真实键盘回调作答，等待写入完成再退出。
      var keypad = tester.widget<NumberKeypad>(find.byType(NumberKeypad));
      for (final digit in generated.first.answerText.split('')) {
        keypad.onNumberTap(digit);
      }
      await tester.pump();
      keypad = tester.widget<NumberKeypad>(find.byType(NumberKeypad));
      await tester.runAsync(() async => keypad.onSubmit());
      await waitForOperationState(
        tester,
        () => container.read(mathAnsweredCountProvider) == 1,
      );
      await drainHiveWritesForTesting(tester);
      await _waitForNext(tester);
      await tester.runAsync(
        () =>
            tester.tap(find.byKey(const ValueKey('math-next-problem-button'))),
      );
      await waitForOperationState(
        tester,
        () => container.read(mathCurrentIndexProvider) == 1,
      );
      expect(container.read(mathCurrentIndexProvider), 1);
      // 模拟应用离开，dispose 保存真实生成题组；修改长期偏好再续练。
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
      final draft = PracticeDraftRepository().get('math')!;
      expect((draft['request'] as Map)['operationCounts'], [2, 3]);
      expect(draft['problems'], original);
      await tester.runAsync(
        () => SettingsRepository().setMathOperationCounts(OperationCounts([1])),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: PageAnimationScope(
              enabled: false,
              child: MathPracticePage(resume: true),
            ),
          ),
        ),
      );
      await waitForOperationState(
        tester,
        () => find.byType(NumberKeypad).evaluate().isNotEmpty,
      );
      expect(
        container.read(mathProblemsProvider).map((p) => p.toJson()),
        original,
      );
      expect(container.read(mathCurrentIndexProvider), 1);
      for (var i = 1; i < 5; i++) {
        await waitForOperationState(tester, () {
          final keypad = find.byType(NumberKeypad);
          return container.read(mathCurrentIndexProvider) == i &&
              keypad.evaluate().isNotEmpty;
        });
        final p = container.read(currentProblemProvider)!;
        keypad = tester.widget<NumberKeypad>(find.byType(NumberKeypad));
        // 第二题故意答错，验证组合题快照进入错题和历史。
        final answer = i == 1 ? '${p.result.asInteger + 1}' : p.answerText;
        for (final digit in answer.split('')) {
          keypad.onNumberTap(digit);
        }
        await tester.pump();
        await waitForOperationState(
          tester,
          () => tester
              .widget<NumberKeypad>(find.byType(NumberKeypad))
              .submitEnabled,
        );
        keypad = tester.widget<NumberKeypad>(find.byType(NumberKeypad));
        await tester.runAsync(() async => keypad.onSubmit());
        await waitForOperationState(
          tester,
          () => container.read(mathAnsweredCountProvider) == i + 1,
        );
        await drainHiveWritesForTesting(tester);
        await _waitForNext(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('math-next-problem-button')),
        );
        await tester.runAsync(
          () => tester.tap(
            find.byKey(const ValueKey('math-next-problem-button')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
      }
      await waitForOperationState(
        tester,
        () =>
            PracticeDraftRepository().get('math') == null &&
            HiveBoxes.mathSessions.values.any((s) => s.totalProblems == 5),
      );
      await drainHiveWritesForTesting(tester);
      final session = HiveBoxes.mathSessions.values.single;
      expect(session.totalProblems, 5);
      expect(session.correctCount, 4);
      expect(session.problemRecords.map((p) => p.problem), original);
      expect(HiveBoxes.mathMistakes.length, 1);
      expect(
        jsonDecode(HiveBoxes.mathMistakes.values.single.problemJson!),
        original[1],
      );
      expect(PracticeDraftRepository().get('math'), isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      await drainHiveWritesForTesting(tester);
      router.dispose();
      container.dispose();
    }
  });
}
