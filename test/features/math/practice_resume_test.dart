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
import 'package:poemath/math_engine/models/vertical_attempt.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
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

class _RecordingSoundService extends SoundService {
  _RecordingSoundService() : super(SettingsRepository());
  int completions = 0;
  @override
  Future<void> playCompletion() async => completions++;
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
  // 意图分流（从口算/竖式卡片进入时，草稿是另一种方案的处理）。
  // 复现路径：普通练习退出留草稿 → 从竖式卡片进入 → 原实现弹恢复框，
  // 点"继续上次"恢复普通题组（劫持入口意图），点"开始新练习"也因
  // consume() 丢弃 setNext 的竖式请求而练成综合 —— 两个分支都偏。
  group('入口意图与草稿方案分流', () {
    /// 返回 container 供断言读取 provider 状态。
    ///
    /// `runAsync` 必须 await：它是真实异步区，不等待就返回会让测试在
    /// build 完成前断言，并在退出时留下未完成的 tester 协程（表现为
    /// 测试进程挂死、10+ 分钟不退出）。
    Future<ProviderContainer> pumpWithIntent(
      WidgetTester tester, {
      required MathPracticeRequest intent,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(nextMathPracticeRequestProvider.notifier).setNext(intent);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: MathPracticePage()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return container;
    }

    testWidgets('竖式入口遇普通草稿：不弹恢复框，直接开新竖式练习', (tester) async {
      // 预置一份**普通**草稿（mode 缺省 = 综合）。
      final draft = _checkpoint(_addition())
        ..remove('completedAt')
        ..['input'] = ''
        ..['records'] = <Object>[];
      await tester.runAsync(() async {
        await PracticeDraftRepository().save('math', draft);
      });

      final container = await pumpWithIntent(
        tester,
        intent: const MathPracticeRequest(
          grade: 2,
          semester: '上',
          count: 2,
          difficulty: DifficultyLevel.medium,
          mode: ProblemMode.vertical,
        ),
      );

      // 不弹恢复框。
      expect(find.text('还有一组未完成的口算'), findsNothing);
      // 直接进入竖式练习（新题组，非草稿恢复）。
      final generated = container.read(mathProblemsProvider);
      expect(
        generated.every((p) => p.mode == ProblemMode.vertical),
        isTrue,
        reason: '从竖式卡片进入必须练竖式',
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
    });

    testWidgets('口算入口遇竖式草稿：同样不弹框，直接开普通练习', (tester) async {
      final draft = _checkpoint(_addition(mode: ProblemMode.vertical))
        ..remove('completedAt')
        ..['input'] = ''
        ..['records'] = <Object>[];
      // 草稿 request 的 mode 须为 vertical。
      draft['request'] = const MathPracticeRequest(
        grade: 2,
        semester: '上',
        count: 1,
        difficulty: DifficultyLevel.medium,
        mode: ProblemMode.vertical,
      ).toJson();
      await tester.runAsync(() async {
        await PracticeDraftRepository().save('math', draft);
      });

      final container = await pumpWithIntent(
        tester,
        intent: const MathPracticeRequest(
          grade: 2,
          semester: '上',
          count: 2,
          difficulty: DifficultyLevel.medium,
          // mode 为 null：口算卡片在偏好非竖式时的常态。
        ),
      );

      expect(find.text('还有一组未完成的口算'), findsNothing);
      final generated = container.read(mathProblemsProvider);
      expect(
        generated.every((p) => p.mode != ProblemMode.vertical),
        isTrue,
        reason: '从口算卡片进入不应练竖式',
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
    });

    testWidgets('无预设请求（如首页直达）遇草稿：仍弹恢复框', (tester) async {
      final draft = _checkpoint(_addition())
        ..remove('completedAt')
        ..['input'] = ''
        ..['records'] = <Object>[];
      await tester.runAsync(() async {
        await PracticeDraftRepository().save('math', draft);
      });

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: MathPracticePage()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('还有一组未完成的口算'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
    });
  });

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
    final sound = _RecordingSoundService();
    await tester.runAsync(() async {
      await PracticeDraftRepository().save('math', _checkpoint(_addition()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mathSessionRepositoryProvider.overrideWithValue(sessions),
            soundServiceProvider.overrideWithValue(sound),
          ],
          child: const MaterialApp(home: MathPracticePage(resume: true)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('练习已恢复，进度或结算暂未保存，请重试'), findsOneWidget);
    expect(find.text('查看成绩'), findsOneWidget);
    expect(sound.completions, 0, reason: '保存失败不播放完成音');
    expect(HiveBoxes.userStats.get('default_stats')!.mathTotalProblems, 1);
    await tester.runAsync(() async {
      await tester.tap(find.text('查看成绩'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final saved = HiveBoxes.mathSessions.values.single;
    expect(sound.completions, 1, reason: '重试成功只播放一次完成音');
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
  for (final (a, b, op, answer, fields) in [
    (6, 5, Operator.multiply, '30', ['tens', 'ones']),
    (95, 27, Operator.add, '122', ['hundreds', 'tens', 'ones']),
    (
      95,
      27,
      Operator.multiply,
      '2565',
      ['thousands', 'hundreds', 'tens', 'ones']
    ),
  ]) {
    testWidgets('竖式$a${op.symbol}$b显示所有结果数位，只填结果即可提交', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = op == Operator.add ? a + b : a * b;
      final problem = MathProblem(
        operands: [NumberValue.fromInt(a), NumberValue.fromInt(b)],
        operators: [op],
        result: NumberValue.fromInt(result),
        mode: ProblemMode.vertical,
        grade: 2,
        semester: '上',
      );
      await tester.runAsync(() async {
        await HiveBoxes.settings.put('sound_enabled', false);
        await HiveBoxes.settings.put('haptic_enabled', false);
        await PracticeDraftRepository().save('math', {
          'sessionId': 'vertical-input-$result',
          'startedAt': DateTime.now().toIso8601String(),
          'elapsedMilliseconds': 0,
          'index': 0,
          'request': const MathPracticeRequest(
            grade: 2,
            semester: '上',
            count: 1,
            difficulty: DifficultyLevel.medium,
            mode: ProblemMode.vertical,
          ).toJson(),
          'problems': [problem.toJson()],
          'records': <Map<String, dynamic>>[],
        });
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MathPracticePage(resume: true)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('输入答案'), findsNothing);
      expect(find.byKey(const ValueKey('vertical_regroup')), findsNothing);
      for (var i = 0; i < fields.length; i++) {
        final selector = find.byKey(ValueKey('vertical_${fields[i]}'));
        expect(selector, findsOneWidget);
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pump();
        final key = find.descendant(
          of: find.byType(NumberKeypad),
          matching: find.text(answer[i]),
        );
        await tester.tap(key);
        await tester.pump();
      }
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.check_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('回答正确！'), findsOneWidget);
      final record = HiveBoxes.mathSessions.values.single.problemRecords.single;
      expect(record.userAnswer, answer);
      expect(record.isCorrect, isTrue);
      expect(HiveBoxes.mathMistakes.values, isEmpty);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(seconds: 5));
    });
  }

  for (final legacy in [true, false]) {
    testWidgets('恢复乘法${legacy ? '旧完整答案' : '新高位作答'}草稿，数位内容可见且可直接提交',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final problem = MathProblem(
        operands: [NumberValue.fromInt(95), NumberValue.fromInt(27)],
        operators: [Operator.multiply],
        result: NumberValue.fromInt(2565),
        mode: ProblemMode.vertical,
        grade: 2,
        semester: '上',
      );
      final attempt = legacy
          ? const VerticalAttempt()
          : const VerticalAttempt(ones: '5', tens: '6', hundreds: '5')
              .withField('thousands', '2');
      await tester.runAsync(() async {
        await HiveBoxes.settings.put('sound_enabled', false);
        await HiveBoxes.settings.put('haptic_enabled', false);
        await PracticeDraftRepository().save('math', {
          'sessionId': 'restore-multiplication-$legacy',
          'startedAt': DateTime.now().toIso8601String(),
          'elapsedMilliseconds': 0,
          'index': 0,
          // 新数位作答优先，不能被残留的完整答案覆盖。
          'input': legacy ? '2565' : '9999',
          'verticalAttempt': attempt.toJson(),
          'verticalField': legacy ? 'ones' : 'thousands',
          'request': const MathPracticeRequest(
            grade: 2,
            semester: '上',
            count: 1,
            difficulty: DifficultyLevel.medium,
            mode: ProblemMode.vertical,
          ).toJson(),
          'problems': [problem.toJson()],
          'records': <Map<String, dynamic>>[],
        });
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MathPracticePage(resume: true)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      for (final label in ['千位：2', '百位：5', '十位：6', '个位：5']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(ValueKey('vertical_${legacy ? 'ones' : 'thousands'}')),
            )
            .selected,
        isTrue,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.check_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('回答正确！'), findsOneWidget);
      final record = HiveBoxes.mathSessions.values.single.problemRecords.single;
      expect(record.userAnswer, '2565');
      expect(record.isCorrect, isTrue);
      expect(
        VerticalAttempt.fromJson(record.attempt!).higherDigits,
        {'thousands': '2'},
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('恢复旧进位判错记录保留历史判定和统计，重开不重复写入', (tester) async {
    final problem = MathProblem(
      operands: [NumberValue.fromInt(38), NumberValue.fromInt(45)],
      operators: [Operator.add],
      result: NumberValue.fromInt(83),
      mode: ProblemMode.vertical,
      grade: 2,
      semester: '上',
    );
    final attempt =
        const VerticalAttempt(ones: '3', tens: '8', regroup: '0').toJson();
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
      await PracticeDraftRepository().save('math', {
        'sessionId': 'legacy-vertical-answer',
        'startedAt': DateTime(2026, 10, 16).toIso8601String(),
        'elapsedMilliseconds': 5000,
        'index': 0,
        'verticalField': 'regroup',
        'verticalAttempt': attempt,
        'request': const MathPracticeRequest(
          grade: 2,
          semester: '上',
          count: 1,
          difficulty: DifficultyLevel.medium,
          mode: ProblemMode.vertical,
        ).toJson(),
        'problems': [problem.toJson()],
        'records': [
          ProblemRecord(
            problemText: problem.problemText,
            answerText: '83',
            userAnswer: '83',
            isCorrect: false,
            problem: problem.toJson(),
            attempt: attempt,
          ).toJson(),
        ],
      });
    });
    for (var run = 0; run < 2; run++) {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MathPracticePage(resume: true)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('再想想'), findsOneWidget);
      expect(find.text('这道题按原练习规则记录为答错；重新练习只检查结果各数位。'), findsOneWidget);
      expect(
        HiveBoxes.mathSessions.values.single.problemRecords.single.isCorrect,
        isFalse,
      );
      expect(
        HiveBoxes.mathMistakes.values.single.errorType,
        VerticalAttempt.errorCategory,
      );
      expect(HiveBoxes.mathMistakes.values.single.wrongCount, 1);
      expect(HiveBoxes.userStats.get('default_stats')!.mathTotalProblems, 1);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
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
  for (final tens in ['7', '8']) {
    testWidgets('窄屏大字恢复旧进位选中项，十位$tens按结果判分并保存草稿', (tester) async {
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
          'verticalField': 'regroup',
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
      expect(find.byKey(const ValueKey('vertical_regroup')), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('vertical_ones')))
            .selected,
        isTrue,
      );
      await tester.runAsync(() async {
        // 不点选个位，直接输入以验证旧 regroup 选中项已恢复到个位。
        await tester.ensureVisible(find.text('3').last);
        await tester.tap(find.text('3').last);
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('vertical_tens')));
        await tester.tap(find.byKey(const ValueKey('vertical_tens')));
        await tester.pump();
        await tester.ensureVisible(find.text(tens).last);
        await tester.tap(find.text(tens).last);
        await tester.pump();
        await tester.ensureVisible(find.byIcon(Icons.check_rounded));
        await tester.tap(find.byIcon(Icons.check_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final record = HiveBoxes.mathSessions.values.single.problemRecords.single;
      expect(record.userAnswer, '${tens}3');
      expect(record.isCorrect, tens == '8');
      expect(record.attempt!['ones'], '3');
      expect(record.attempt!['tens'], tens);
      expect(record.attempt!['regroup'], isEmpty);
      if (tens == '7') {
        expect(
          HiveBoxes.mathMistakes.values.single.attemptJson,
          contains('"tens":"7"'),
        );
      } else {
        expect(HiveBoxes.mathMistakes.values, isEmpty);
      }
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
}
