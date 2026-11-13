import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/widgets/vertical_process_input.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  void expectFullWidthProgress(WidgetTester tester) {
    final progress = find.byType(LinearProgressIndicator);
    expect(progress, findsOneWidget);
    final rect = tester.getRect(progress);
    final pixelRatio = tester.view.devicePixelRatio;
    expect(rect.left, tester.view.padding.left / pixelRatio + SpacingTokens.md);
    expect(
      rect.right,
      (tester.view.physicalSize.width - tester.view.padding.right) /
              pixelRatio -
          SpacingTokens.md,
    );
  }

  void expectCenteredRightControls(WidgetTester tester, Finder controls) {
    final progress = tester.getRect(find.byType(LinearProgressIndicator));
    final availableTop = progress.bottom + SpacingTokens.sm;
    final availableBottom =
        (tester.view.physicalSize.height - tester.view.padding.bottom) /
        tester.view.devicePixelRatio;
    expect(
      tester.getRect(controls).center.dy,
      (availableTop + availableBottom) / 2,
    );
  }

  Future<void> openPractice(WidgetTester tester, ProblemMode mode) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(914, 411);
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await SettingsRepository().setSoundEnabled(false);
      await SettingsRepository().setHapticEnabled(false);
    });
    final problem = MathProblem(
      operands: [NumberValue.fromInt(23), NumberValue.fromInt(14)],
      operators: [Operator.add],
      result: NumberValue.fromInt(37),
      grade: 2,
      semester: '上',
      mode: mode,
      compareRelation: mode == ProblemMode.compare
          ? CompareRelation.lessThan
          : null,
      compareTarget: mode == ProblemMode.compare
          ? NumberValue.fromInt(40)
          : null,
    );
    await tester.runAsync(
      () => PracticeDraftRepository().save('math', {
        'sessionId': 'layout-practice',
        'startedAt': DateTime(2026, 11, 8).toIso8601String(),
        'elapsedMilliseconds': 0,
        'index': 0,
        'input': '',
        'request': MathPracticeRequest(
          grade: 2,
          semester: '上',
          count: 1,
          mode: mode,
          difficulty: DifficultyLevel.medium,
        ).toJson(),
        'problems': [problem.toJson()],
        'records': <Object>[],
      }),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PageAnimationScope(
            enabled: false,
            child: MathPracticePage(resume: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('q_0')), findsOneWidget);
    expectFullWidthProgress(tester);
  }

  Future<void> closePractice(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await drainHiveWritesForTesting(tester);
  }

  testWidgets('短横屏同时显示题目、输入和键盘，旋转保持输入并可提交', (tester) async {
    await openPractice(tester, ProblemMode.findResult);
    expect(
      find.byKey(const ValueKey('math-practice-split-layout')),
      findsOneWidget,
    );
    final question = tester.getRect(find.byKey(const ValueKey('q_0')));
    final input = tester.getRect(find.text('输入答案'));
    final keypad = tester.getRect(find.byType(NumberKeypad));
    expectCenteredRightControls(tester, find.byType(NumberKeypad));
    final progress = tester.getRect(find.byType(LinearProgressIndicator));
    expect(progress.bottom, lessThan(question.top));
    expect(progress.bottom, lessThanOrEqualTo(keypad.top));
    expect(question.top, greaterThanOrEqualTo(84));
    expect(question.bottom, lessThan(input.top));
    expect(input.bottom, lessThanOrEqualTo(387));
    expect(input.right, lessThan(keypad.left));
    expect(
      tester.getRect(find.byIcon(Icons.check_rounded)).bottom,
      lessThanOrEqualTo(387),
    );

    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('7'));
    await tester.pump();
    expect(find.text('37'), findsOneWidget);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    expectFullWidthProgress(tester);
    expectCenteredRightControls(tester, find.byType(NumberKeypad));
    expect(find.text('37'), findsOneWidget);
    tester.view.physicalSize = const Size(411, 914);
    await tester.pump();
    expectFullWidthProgress(tester);
    expect(find.text('37'), findsOneWidget);
    expect(
      tester.getRect(find.text('37')).bottom,
      lessThan(tester.getRect(find.byType(NumberKeypad)).top),
    );
    tester.view.physicalSize = const Size(914, 411);
    await tester.pump();
    expectFullWidthProgress(tester);
    expectCenteredRightControls(tester, find.byType(NumberKeypad));
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check_rounded));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '查看成绩'),
      );
      if (button.onPressed != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final correctFeedback = find.text('回答正确！');
    expect(correctFeedback, findsOneWidget);
    expect(
      find.ancestor(of: correctFeedback, matching: find.byType(ColoredCard)),
      findsNothing,
    );
    final correctIcon = tester.getRect(find.byIcon(Icons.check_circle_rounded));
    final correctText = tester.getRect(correctFeedback);
    final questionRect = tester.getRect(find.byKey(const ValueKey('q_0')));
    expect(correctIcon.right, lessThan(correctText.left));
    expect(correctIcon.left, greaterThan(questionRect.right));
    expect(correctIcon.center.dy, closeTo(questionRect.center.dy, 1));
    expect(
      (questionRect.left + correctText.right) / 2,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        1,
      ),
    );
    expect(find.text('查看成绩').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('math-practice-split-layout')),
      findsNothing,
    );
    expect(find.byType(NumberKeypad), findsNothing);
    final stepsButton = find.widgetWithText(TextButton, '查看解题步骤');
    final nextButton = find.byKey(const ValueKey('math-next-problem-button'));
    expect(stepsButton, findsOneWidget);
    expect(nextButton, findsOneWidget);
    final stepsRect = tester.getRect(stepsButton);
    final nextRect = tester.getRect(nextButton);
    expect(nextRect.left, greaterThan(stepsRect.right));
    expect(nextRect.center.dy, closeTo(stepsRect.center.dy, 1));
    final labelRect = tester.getRect(find.text('查看成绩'));
    final arrowRect = tester.getRect(find.byIcon(Icons.arrow_forward_rounded));
    expect(arrowRect.left, greaterThan(labelRect.right));
    expect(arrowRect.center.dy, closeTo(labelRect.center.dy, 1));
    final revealedQuestion = find.text('23 + 14 = 37');
    expect(revealedQuestion, findsOneWidget);
    tester.view.physicalSize = const Size(411, 914);
    await tester.pump();
    expect(revealedQuestion, findsOneWidget);
    expect(correctFeedback, findsOneWidget);
    await tester.tap(stepsButton);
    await tester.pump();
    final stepsContent = find.byKey(
      const ValueKey('math-practice-steps-content'),
    );
    expect(stepsContent, findsOneWidget);
    expect(
      find.descendant(of: stepsContent, matching: find.byType(ColoredCard)),
      findsNothing,
    );
    final stepsContentRect = tester.getRect(stepsContent);
    expect(
      stepsContentRect.center.dx,
      closeTo(tester.view.physicalSize.width / 2, 1),
    );
    expect(
      stepsContentRect.width,
      lessThan(tester.view.physicalSize.width - SpacingTokens.md * 2),
    );
    final unitsStep = tester.getRect(find.textContaining('个位：'));
    final tensStep = tester.getRect(find.textContaining('十位：'));
    final summaryStep = tester.getRect(find.textContaining('所以'));
    expect(unitsStep.left, closeTo(tensStep.left, 1));
    expect(unitsStep.left, closeTo(summaryStep.left, 1));
    final firstStepMarker = tester.getRect(
      find.byKey(const ValueKey('math-practice-step-marker-1')),
    );
    final firstStepText = tester.getRect(find.textContaining('个位：'));
    expect(firstStepMarker.center.dy, closeTo(firstStepText.center.dy, 1));
    final secondStepMarker = tester.getRect(
      find.byKey(const ValueKey('math-practice-step-marker-2')),
    );
    expect(secondStepMarker.center.dy, closeTo(tensStep.center.dy, 1));
    final summaryStepMarker = tester.getRect(
      find.byKey(const ValueKey('math-practice-step-marker-3')),
    );
    expect(summaryStepMarker.center.dy, closeTo(summaryStep.center.dy, 1));
    final finalResult = find.text('最终结果：37');
    expect(finalResult, findsOneWidget);
    final finalResultMarker = tester.getRect(
      find.byKey(const ValueKey('math-practice-step-marker-4')),
    );
    expect(
      finalResultMarker.center.dy,
      closeTo(tester.getRect(finalResult).center.dy, 1),
    );
    expect(tester.takeException(), isNull);
    await closePractice(tester);
  });

  testWidgets('答错后题目填入用户答案，错误反馈紧随题目', (tester) async {
    await openPractice(tester, ProblemMode.findResult);
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('6'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check_rounded));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '查看成绩'),
      );
      if (button.onPressed != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    final wrongQuestion = find.text('23 + 14 = 36');
    final wrongFeedback = find.text('再想想');
    final correctAnswer = find.text('正确答案：37');
    expect(wrongQuestion, findsOneWidget);
    expect(wrongFeedback, findsOneWidget);
    expect(correctAnswer, findsOneWidget);
    expect(
      find.ancestor(of: wrongFeedback, matching: find.byType(ColoredCard)),
      findsNothing,
    );
    var questionRect = tester.getRect(find.byKey(const ValueKey('q_0')));
    var feedbackRect = tester.getRect(wrongFeedback);
    var answerRect = tester.getRect(correctAnswer);
    var iconRect = tester.getRect(find.byIcon(Icons.lightbulb_outline_rounded));
    expect(iconRect.left, greaterThan(questionRect.right));
    expect(iconRect.right, lessThan(feedbackRect.left));
    expect(feedbackRect.right, lessThan(answerRect.left));
    expect(feedbackRect.center.dy, closeTo(answerRect.center.dy, 1));
    expect(iconRect.center.dy, closeTo(feedbackRect.center.dy, 1));
    expect(
      (questionRect.left + answerRect.right) / 2,
      closeTo(tester.view.physicalSize.width / 2, 1),
    );

    tester.view.physicalSize = const Size(411, 914);
    await tester.pump();
    expect(wrongQuestion, findsOneWidget);
    expect(wrongFeedback, findsOneWidget);
    questionRect = tester.getRect(find.byKey(const ValueKey('q_0')));
    feedbackRect = tester.getRect(wrongFeedback);
    answerRect = tester.getRect(correctAnswer);
    iconRect = tester.getRect(find.byIcon(Icons.lightbulb_outline_rounded));
    expect(iconRect.top, greaterThan(questionRect.bottom));
    expect(feedbackRect.center.dy, closeTo(answerRect.center.dy, 1));
    expect(
      (iconRect.left + answerRect.right) / 2,
      closeTo(tester.view.physicalSize.width / 2, 1),
    );
    expect(
      find.ancestor(of: wrongFeedback, matching: find.byType(ColoredCard)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await closePractice(tester);
  });

  testWidgets('短横屏竖式输入可滚动而键盘位置保持固定', (tester) async {
    await openPractice(tester, ProblemMode.vertical);
    final input = find.byType(VerticalProcessInput);
    final keypadBefore = tester.getRect(find.byType(NumberKeypad));
    expectCenteredRightControls(tester, find.byType(NumberKeypad));
    await tester.ensureVisible(input);
    await tester.pump();
    expect(input.hitTestable(), findsOneWidget);
    expect(tester.getRect(find.byType(NumberKeypad)), keypadBefore);
    expect(find.byIcon(Icons.check_rounded).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closePractice(tester);
  });

  testWidgets('短横屏比大小的三个操作与题目并列可用', (tester) async {
    await openPractice(tester, ProblemMode.compare);
    final question = tester.getRect(find.byKey(const ValueKey('q_0')));
    for (final symbol in ['<', '=', '>']) {
      final button = find.widgetWithText(OutlinedButton, symbol);
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.getRect(button).left, greaterThan(question.right));
      expectCenteredRightControls(tester, button);
    }
    await tester.runAsync(() async {
      await tester.tap(find.text('>'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '查看成绩'),
      );
      if (button.onPressed != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('23 + 14 > 40'), findsOneWidget);
    expect(find.text('再想想'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closePractice(tester);
  });
}
