import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
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
  }

  Future<void> closePractice(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await drainHiveWritesForTesting(tester);
  }

  testWidgets('短横屏同时显示题目、输入和键盘，旋转保持输入并可提交', (tester) async {
    await openPractice(tester, ProblemMode.findResult);
    final question = tester.getRect(find.byKey(const ValueKey('q_0')));
    final input = tester.getRect(find.text('输入答案'));
    final keypad = tester.getRect(find.byType(NumberKeypad));
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
    tester.view.physicalSize = const Size(411, 914);
    await tester.pump();
    expect(find.text('37'), findsOneWidget);
    expect(
      tester.getRect(find.text('37')).bottom,
      lessThan(tester.getRect(find.byType(NumberKeypad)).top),
    );
    tester.view.physicalSize = const Size(914, 411);
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
    expect(find.text('回答正确！'), findsOneWidget);
    expect(find.text('查看成绩').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closePractice(tester);
  });

  testWidgets('短横屏竖式输入可滚动而键盘位置保持固定', (tester) async {
    await openPractice(tester, ProblemMode.vertical);
    final input = find.byType(VerticalProcessInput);
    final keypadBefore = tester.getRect(find.byType(NumberKeypad));
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
    }
    expect(tester.takeException(), isNull);
    await closePractice(tester);
  });
}
