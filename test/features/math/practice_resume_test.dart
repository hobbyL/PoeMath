import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/practice_clock.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import '../../helpers/hive_test_helper.dart';

class _FailFinalSessionOnce extends MathSessionRepository {
  bool fail = true;

  @override
  Future<void> save(MathSession session) async {
    if (fail && session.starsEarned > 0) {
      fail = false;
      throw StateError('模拟一次结算写入失败');
    }
    await super.save(session);
  }
}

MathProblem _addition({ProblemMode mode = ProblemMode.findResult}) =>
    MathProblem(
      operands: [NumberValue.fromInt(23), NumberValue.fromInt(14)],
      operators: [Operator.add],
      result: NumberValue.fromInt(37),
      grade: 2,
      mode: mode,
      semester: '上',
      skillId: 'addition',
    );

Map<String, dynamic> _checkpoint(MathProblem problem) => {
      'sessionId': 'pending-math-final',
      'startedAt': DateTime(2026, 10, 16, 10).toIso8601String(),
      'completedAt': DateTime(2026, 10, 16, 10, 1).toIso8601String(),
      'elapsedMilliseconds': 60000,
      'index': 0,
      'input': '37',
      'request': const MathPracticeRequest(
        grade: 2,
        semester: '上',
        count: 1,
        difficulty: DifficultyLevel.medium,
      ).toJson(),
      'problems': [problem.toJson()],
      'records': [
        ProblemRecord(
          problemText: problem.problemText,
          answerText: '37',
          userAnswer: '37',
          isCorrect: true,
          problem: problem.toJson(),
        ).toJson(),
      ],
    };

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);
  for (final mode in [ProblemMode.findResult, ProblemMode.vertical]) {
    testWidgets('${mode.name} 键盘贴底且滚动题目时不移动，按键避开手势区', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = _checkpoint(_addition(mode: mode))
        ..remove('completedAt')
        ..['input'] = ''
        ..['records'] = <Object>[];
      await tester.runAsync(() async {
        await PracticeDraftRepository().save('math', draft);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                  padding: const EdgeInsets.only(bottom: 24),
                  viewPadding: const EdgeInsets.only(bottom: 24),
                ),
                child: child!,
              ),
              home: const MathPracticePage(resume: true),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final keypad = find.byType(NumberKeypad);
      final initial = tester.getRect(keypad);
      expect(initial.bottom, closeTo(640, 0.1));
      expect(initial.left, closeTo(0, 0.1));
      expect(initial.right, closeTo(320, 0.1));
      final submitTarget = find.ancestor(
        of: find.byIcon(Icons.check_rounded),
        matching: find.byType(InkWell),
      );
      expect(tester.getRect(submitTarget).bottom, lessThanOrEqualTo(616));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -150),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(keypad), initial);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
    });
  }
  testWidgets('口算恢复后结算失败保留重试，时间和统计不重复', (tester) async {
    final sessions = _FailFinalSessionOnce();
    await tester.runAsync(() async {
      await PracticeDraftRepository().save('math', _checkpoint(_addition()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mathSessionRepositoryProvider.overrideWithValue(sessions),
          ],
          child: const MaterialApp(home: MathPracticePage(resume: true)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('练习已恢复，进度或结算暂未保存，请重试'), findsOneWidget);
    expect(find.text('查看成绩'), findsOneWidget);
    expect(HiveBoxes.userStats.get('default_stats')!.mathTotalProblems, 1);
    await tester.runAsync(() async {
      await tester.tap(find.text('查看成绩'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final saved = HiveBoxes.mathSessions.values.single;
    expect(saved.durationSeconds, 60);
    expect(saved.finishedAt, DateTime(2026, 10, 16, 10, 1));
    expect(HiveBoxes.learningActivities.length, 1);
    expect(HiveBoxes.userStats.get('default_stats')!.mathTotalProblems, 1);
    expect(PracticeDraftRepository().get('math'), isNull);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(seconds: 5));
  });
  testWidgets('损坏草稿解析失败不显示上一组题，离页不覆盖原草稿', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final original = _checkpoint(_addition())..['startedAt'] = 'invalid';
    await tester.runAsync(() async {
      await PracticeDraftRepository().save('math', original);
      container.read(mathProblemsProvider.notifier).state = [_addition()];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MathPracticePage(resume: true)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('上次练习暂时无法恢复，请返回首页放弃草稿后重试'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(HiveBoxes.mathSessions.isEmpty, isTrue);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(PracticeDraftRepository().get('math')!['startedAt'], 'invalid');
  });
  testWidgets('恢复相同题组、位置、输入与已答结果，多次打开不重复统计', (tester) async {
    final first = MathProblem(
      operands: [NumberValue.fromInt(12), NumberValue.fromInt(4)],
      operators: [Operator.subtract],
      result: NumberValue.fromInt(8),
      grade: 2,
      mode: ProblemMode.findResult,
      difficulty: 2,
      semester: '上',
      skillId: 'subtraction',
    );
    final second = MathProblem(
      operands: [NumberValue.fromInt(23), NumberValue.fromInt(14)],
      operators: [Operator.add],
      result: NumberValue.fromInt(37),
      grade: 2,
      mode: ProblemMode.findResult,
      difficulty: 2,
      semester: '上',
      skillId: 'addition',
    );
    await tester.runAsync(() async {
      await PracticeDraftRepository().save('math', {
        'sessionId': 'resume-fixture',
        'startedAt': DateTime(2026, 10, 16).toIso8601String(),
        'elapsedMilliseconds': 12000,
        'index': 1,
        'input': '3',
        'request': const MathPracticeRequest(
          grade: 2,
          semester: '上',
          count: 2,
          difficulty: DifficultyLevel.medium,
        ).toJson(),
        'problems': [first.toJson(), second.toJson()],
        'records': [
          ProblemRecord(
            problemText: first.problemText,
            answerText: '8',
            userAnswer: '8',
            isCorrect: true,
            skillId: first.skillId,
            problem: first.toJson(),
          ).toJson(),
        ],
      });
    });
    for (var run = 0; run < 2; run++) {
      final container = ProviderContainer();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: MathPracticePage(resume: true)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        container.read(mathProblemsProvider).map((p) => p.toJson()),
        [first.toJson(), second.toJson()],
      );
      expect(container.read(mathCurrentIndexProvider), 1);
      expect(container.read(mathAnsweredCountProvider), 1);
      expect(find.text('3'), findsWidgets);
      expect(HiveBoxes.userStats.get('default_stats')!.mathTotalProblems, 1);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      container.dispose();
      await tester.pump(const Duration(seconds: 5));
    }
  });
  testWidgets('前台时钟暂停期间不累计，结算后不能重新启动', (tester) async {
    final clock = PracticeClock();
    addTearDown(clock.dispose);
    clock.start(elapsedMilliseconds: 5000);
    clock.didChangeAppLifecycleState(AppLifecycleState.paused);
    final paused = clock.elapsedMilliseconds;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(clock.elapsedMilliseconds, paused);
    clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(clock.elapsedMilliseconds, greaterThan(paused));
    clock.finish();
    final finished = clock.elapsedMilliseconds;
    clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(clock.elapsedMilliseconds, finished);
  });
  testWidgets('窄屏大字号逐列作答：结果83但进位填0不能通过，草稿和错题保留过程', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = MathProblem(
      operands: [NumberValue.fromInt(38), NumberValue.fromInt(45)],
      operators: [Operator.add],
      result: NumberValue.fromInt(83),
      mode: ProblemMode.vertical,
      grade: 2,
      semester: '上',
      skillId: 'addition_carry',
    );
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
      await PracticeDraftRepository().save('math', {
        'sessionId': 'vertical-fixture',
        'startedAt': DateTime.now().toIso8601String(),
        'elapsedMilliseconds': 5000,
        'index': 0,
        'input': '',
        'request': const MathPracticeRequest(
          grade: 2,
          semester: '上',
          count: 1,
          difficulty: DifficultyLevel.medium,
          mode: ProblemMode.vertical,
        ).toJson(),
        'problems': [p.toJson()],
        'records': <Map<String, dynamic>>[],
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const MathPracticePage(resume: true),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await tester.ensureVisible(find.byKey(const ValueKey('vertical_ones')));
      await tester.tap(find.byKey(const ValueKey('vertical_ones')));
      await tester.pump();
      await tester.ensureVisible(find.text('3').last);
      await tester.tap(find.text('3').last);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('vertical_tens')));
      await tester.tap(find.byKey(const ValueKey('vertical_tens')));
      await tester.pump();
      await tester.ensureVisible(find.text('8').last);
      await tester.tap(find.text('8').last);
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const ValueKey('vertical_regroup')));
      await tester.tap(find.byKey(const ValueKey('vertical_regroup')));
      await tester.pump();
      await tester.ensureVisible(find.text('0').last);
      await tester.tap(find.text('0').last);
      await tester.pump();
      await tester.ensureVisible(find.byIcon(Icons.check_rounded));
      await tester.tap(find.byIcon(Icons.check_rounded));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final record = HiveBoxes.mathSessions.values.single.problemRecords.single;
    expect(record.userAnswer, '83');
    expect(record.isCorrect, isFalse);
    expect(record.attempt!['regroup'], '0');
    expect(
      HiveBoxes.mathMistakes.values.single.attemptJson,
      contains('"regroup":"0"'),
    );
    expect(
      PracticeDraftRepository().get('math')!['verticalAttempt'],
      record.attempt,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(seconds: 5));
  });
}
