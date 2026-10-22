// test/features/math/math_challenge_page_test.dart
//
// 限时挑战页回归测试：
// ① 时间进度条比例的纯函数（原 clamp 上下界反转，续命模式倒计时必崩）
// ② 续命模式真实倒计时 1 秒后页面不抛异常（P0-1 的端到端复现）

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/math/math_challenge_page.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/widgets/vertical_calc_widget.dart';
import 'package:poemath/features/math/widgets/vertical_process_input.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';

import '../../helpers/hive_test_helper.dart';

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: MathChallengePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('challengeTimeRatio', () {
    test('续命模式剩余秒数小于初始值时按初始值作分母', () {
      // 回归点：旧实现 clamp(60, 59) 的下界大于上界，必抛 ArgumentError。
      final ratio = challengeTimeRatio(
        remainingSeconds: 59,
        initialSeconds: 60,
        extending: true,
      );
      expect(ratio, closeTo(59 / 60, 1e-9));
      expect(ratio, lessThan(1.0));
    });

    test('续命模式答对加时超过初始值时比例封顶为 1.0', () {
      expect(
        challengeTimeRatio(
          remainingSeconds: 62,
          initialSeconds: 60,
          extending: true,
        ),
        1.0,
      );
      expect(
        challengeTimeRatio(
          remainingSeconds: 180,
          initialSeconds: 60,
          extending: true,
        ),
        1.0,
      );
    });

    test('固定模式始终以初始值作分母', () {
      expect(
        challengeTimeRatio(
          remainingSeconds: 30,
          initialSeconds: 60,
          extending: false,
        ),
        0.5,
      );
      // 固定模式不加时，但即便传入超额秒数也不改变分母语义。
      expect(
        challengeTimeRatio(
          remainingSeconds: 62,
          initialSeconds: 60,
          extending: false,
        ),
        closeTo(62 / 60, 1e-9),
      );
    });

    test('时间耗尽时比例为 0 且不除零', () {
      expect(
        challengeTimeRatio(
          remainingSeconds: 0,
          initialSeconds: 60,
          extending: true,
        ),
        0.0,
      );
    });
  });

  group('MathChallengePage 倒计时', () {
    setUp(() async {
      await setUpHiveForTesting();
      // 关闭音效，避免 widget 测试触发 AudioPlayer 平台通道。
      await HiveBoxes.settings.put('sound_enabled', false);
    });

    tearDown(() async {
      await tearDownHiveForTesting();
    });

    testWidgets('竖式挑战无需填进退位，错误结果保存各数位和固定册次', (tester) async {
      await tester.runAsync(() async {
        await SettingsRepository().setLearningBackground(2, '上');
        await HiveBoxes.settings.put('math_difficulty', 'medium');
      });
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MathChallengePage(random: Random(3))),
        ),
      );
      await tester.pumpAndSettle();
      // 计算方案已由 ChoiceChip 改为 SegmentedButton。
      await tester.tap(find.widgetWithText(SegmentedButton<bool>, '竖式'));
      await tester.tap(find.text('固定时间'));
      await tester.tap(find.text('开始挑战'));
      await tester.pump();
      expect(find.byType(VerticalProcessInput), findsOneWidget);
      expect(find.byType(NumberKeypad), findsOneWidget);
      // `find.byTooltip` 命中 Tooltip 内部节点（Flutter 3.44 为
      // `RawTooltip`），不是外层的 IconButton——直接 widget<IconButton>
      // 会抛 `type 'RawTooltip' is not a subtype of type 'IconButton'`。
      // 按祖先关系定位到真正的 IconButton。
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('挑战记录'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      final problem = tester
          .widget<VerticalCalcWidget>(find.byType(VerticalCalcWidget))
          .problem;
      expect(problem.mode, ProblemMode.vertical);
      final a = problem.operands[0].asInteger;
      final b = problem.operands[1].asInteger;
      final correctAnswer = switch (problem.operators.single) {
        Operator.add => a + b,
        Operator.subtract => a - b,
        Operator.multiply => a * b,
        Operator.divide => throw StateError('竖式挑战不应生成除法'),
      };
      final fields = VerticalAttempt.fieldsFor(problem);
      final wrongAnswer = (correctAnswer == 44 ? 45 : 44)
          .toString()
          .padLeft(fields.length, '0');
      expect(find.byKey(const ValueKey('vertical_regroup')), findsNothing);
      for (var i = 0; i < fields.length; i++) {
        await tester.tap(find.byKey(ValueKey('vertical_${fields[i].$1}')));
        await tester.pump();
        await tester.tap(find.descendant(
          of: find.byType(NumberKeypad),
          matching: find.text(wrongAnswer[i]),
        ),);
        await tester.pump();
      }
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.check_rounded));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(find.text('已答 1 题 · 正确 0 题'), findsOneWidget);
      expect(find.text('0 分'), findsOneWidget);
      final mistake = HiveBoxes.mathMistakes.values.single;
      expect(mistake.userAnswer, wrongAnswer);
      expect(mistake.correctAnswer, '$correctAnswer');
      expect(mistake.errorType, 'vertical_process');
      final attempt = jsonDecode(mistake.attemptJson!) as Map;
      for (var i = 0; i < fields.length; i++) {
        expect(attempt[fields[i].$1], wrongAnswer[i]);
      }
      expect(attempt['regroup'], isEmpty);
      expect(mistake.problemJson, isNotNull);
      // 外部册次变化（现只能经学习背景写 Hive）不能改变已开始的挑战
      // 题组及最终记录。
      await tester.runAsync(() async {
        await HiveBoxes.settings.put('selected_grade', 1);
        await HiveBoxes.settings.put('selected_semester', '下');
      });
      container.invalidate(settingsRepositoryProvider);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<VerticalCalcWidget>(find.byType(VerticalCalcWidget))
            .problem
            .grade,
        2,
      );
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      final record = HiveBoxes.challengeRecords.values.single;
      expect(record.calculationMode, 'vertical');
      expect(record.grade, 2);
      expect(record.semester, '上');
      expect(record.difficulty, 'medium');
      expect(record.totalAnswered, 1);
      expect(record.correctCount, 0);
      expect(tester.takeException(), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('续命模式开始挑战后第 1 秒不抛异常且进度条未溢出', (tester) async {
      await _pumpPage(tester);

      // 默认即续命模式。
      expect(find.text('开始挑战'), findsOneWidget);
      await tester.tap(find.text('开始挑战'));
      await tester.pump();

      expect(find.text('60s'), findsOneWidget);

      // 推进 1 秒：旧实现在这里抛 ArgumentError 并渲染红屏。
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.text('59s'), findsOneWidget);

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(59 / 60, 1e-9));

      // 收尾：让页面销毁以取消 Timer。
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('固定模式开始挑战后第 1 秒不抛异常', (tester) async {
      await _pumpPage(tester);

      await tester.tap(find.text('固定时间'));
      await tester.pump();
      await tester.tap(find.text('开始挑战'));
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.text('59s'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('换题前重复提交同一答案只计一次分，换题后可以继续作答', (tester) async {
      await tester
          .runAsync(() => HiveBoxes.settings.put('math_difficulty', 'easy'));
      await _pumpPage(tester);
      await tester.tap(find.text('开始挑战'));
      await tester.pump();

      String answer() {
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data ?? '')
            .firstWhere((text) => text.endsWith('= ?'));
        final numbers = RegExp(r'\d+')
            .allMatches(text)
            .map((match) => int.parse(match.group(0)!))
            .toList();
        expect(numbers, hasLength(2));
        return '${text.contains('+') ? numbers[0] + numbers[1] : numbers[0] - numbers[1]}';
      }

      final firstAnswer = answer();
      await tester.enterText(find.byType(TextField), firstAnswer);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(find.text('已答 1 题 · 正确 1 题'), findsOneWidget);
      expect(find.text('10 分'), findsOneWidget);
      expect(find.text('63s'), findsOneWidget);

      await tester.enterText(find.byType(TextField), firstAnswer);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 399));
      expect(find.text('已答 1 题 · 正确 1 题'), findsOneWidget);
      expect(find.text('10 分'), findsOneWidget);
      expect(find.text('63s'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.enterText(find.byType(TextField), answer());
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(find.text('已答 2 题 · 正确 2 题'), findsOneWidget);
      expect(find.text('20 分'), findsOneWidget);
      expect(find.text('66s'), findsOneWidget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
