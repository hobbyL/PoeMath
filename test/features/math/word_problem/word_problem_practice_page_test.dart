// test/features/math/word_problem/word_problem_practice_page_test.dart
//
// 练习页 widget 测试：判分、答错写错题本、recordAttempt 状态、
// 结算写 MathSession(problemType: 'llm_word_problem')。
//
// 说明：testWidgets 处于 FakeAsync 区，真实 Hive 落盘永不完成。
// 提交答案/查看成绩的写入链无对话框依赖，按 settings_page_test
// 先例把触发写入的 tap 放入 tester.runAsync，在真实异步区完成。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/haptic_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/word_problem/word_problem_practice_page.dart';

import '../../../helpers/hive_test_helper.dart';

/// 触觉在测试环境无平台通道，覆写为 no-op。
class _NoopHapticService extends HapticService {
  _NoopHapticService() : super(SettingsRepository());

  @override
  Future<void> medium() async {}
  @override
  Future<void> heavy() async {}
}

LlmProblem _problem({
  required String id,
  required String questionText,
  required int answer,
  List<int> operands = const [12, 4],
  List<String> operators = const ['-'],
  String profileId = 'default',
  int grade = 2,
  String semester = '上',
  String topic = 'subtraction',
  bool done = false,
  DateTime? createdAt,
}) {
  return LlmProblem(
    id: id,
    profileId: profileId,
    questionText: questionText,
    unit: '个',
    operands: operands,
    operators: operators,
    answer: answer,
    explanation: '讲解：用减法计算。',
    batchId: 'batch_1',
    createdAt: createdAt ?? DateTime(2026, 10, 1),
    grade: grade,
    semester: semester,
    topic: topic,
    difficulty: 2,
    done: done,
  );
}

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

Widget _wrap(Widget child, {MathSessionRepository? sessions}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(
        path: AppRoutes.wordProblemLibrary,
        builder: (_, __) => const Scaffold(body: Text('返回应用题题库')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      hapticServiceProvider.overrideWithValue(_NoopHapticService()),
      if (sessions != null)
        mathSessionRepositoryProvider.overrideWithValue(sessions),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// 输入答案并提交。提交触发的写入链放入真实异步区完成。
Future<void> _answer(WidgetTester tester, String digits) async {
  await tester.runAsync(() async {
    for (final digit in digits.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
  });
  await _waitUntil(
    tester,
    () => tester.widget<NumberKeypad>(find.byType(NumberKeypad)).submitEnabled,
  );
  await tester.runAsync(() async {
    await tester.tap(find.byIcon(Icons.check_rounded));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() completed,
) async {
  await tester.pump();
  for (var i = 0; i < 100 && !completed(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(completed(), isTrue, reason: '练习异步流程未完成');
}

Future<void> _startPractice(
  WidgetTester tester, {
  required List<LlmProblem> current,
  required List<LlmProblem> library,
}) async {
  await tester.runAsync(() async {
    await HiveBoxes.settings.put('sound_enabled', false);
    await HiveBoxes.settings.put('haptic_enabled', false);
    for (final p in library) {
      await HiveBoxes.llmProblems.put('${p.profileId}_${p.id}', p);
    }
    await tester.pumpWidget(_wrap(WordProblemPracticePage(problems: current)));
  });
  await _waitUntil(tester, () => PracticeDraftRepository().get('word') != null);
}

Future<void> _finishRound(WidgetTester tester, List<int> answers) async {
  for (var i = 0; i < answers.length; i++) {
    await _waitUntil(
      tester,
      () => find.byIcon(Icons.check_rounded).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(seconds: 1));
    await _answer(tester, '${answers[i]}');
    final label = i == answers.length - 1 ? '查看成绩' : '下一题';
    final button = find.widgetWithText(FilledButton, label);
    await _waitUntil(
      tester,
      () =>
          button.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(button).onPressed != null,
    );
    await tester.runAsync(() => tester.tap(button));
    await tester.pump();
  }
  await _waitUntil(tester, () => find.text('再练一组').evaluate().isNotEmpty);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _closePractice(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pump();
  await drainHiveWritesForTesting(tester);
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    // 关闭音效，避免 AudioPlayer 平台通道（poem_quiz_page_test 先例）。
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('单题再练换成同类未做题，排除原题及同题面并保存新草稿', (tester) async {
    final first = _problem(id: 'first', questionText: '第一道苹果题', answer: 8);
    final next = _problem(id: 'next', questionText: '第二道蝴蝶题', answer: 7);
    final old = _problem(
      id: 'old',
      questionText: '已经做过的题',
      answer: 6,
      done: true,
      createdAt: DateTime(2026, 10, 2),
    );
    await _startPractice(
      tester,
      current: [
        first,
      ],
      library: [
        first,
        old,
        next,
        _problem(id: 'duplicate', questionText: first.questionText, answer: 8),
        _problem(id: 'grade', questionText: '其他年级', answer: 8, grade: 3),
        _problem(
          id: 'semester',
          questionText: '其他学期',
          answer: 8,
          semester: '下',
        ),
        _problem(
          id: 'topic',
          questionText: '其他知识点',
          answer: 8,
          topic: 'addition',
        ),
        _problem(
          id: 'profile',
          questionText: '其他档案',
          answer: 8,
          profileId: 'other',
        ),
      ],
    );
    await _finishRound(tester, [8]);
    final firstSession = HiveBoxes.mathSessions.values.single.id;
    expect(PracticeDraftRepository().get('word'), isNull);

    await tester.runAsync(() => tester.tap(find.text('再练一组')));
    await _waitUntil(
      tester,
      () => PracticeDraftRepository().get('word') != null,
    );
    expect(find.text(next.questionText), findsOneWidget);
    expect(find.text(first.questionText), findsNothing);
    expect(find.text('输入答案'), findsOneWidget);
    expect(find.text('✓ 0'), findsOneWidget);
    final draft = PracticeDraftRepository().get('word')!;
    expect((draft['problems'] as List).single['id'], next.id);
    expect(draft['sessionId'], isNot(firstSession));
    expect(draft['index'], 0);
    expect(draft['input'], '');
    expect(draft['records'], isEmpty);
    expect(draft['completedAt'], isNull);

    await _finishRound(tester, [7]);
    expect(HiveBoxes.mathSessions.length, 2);
    expect(HiveBoxes.llmProblems.get('default_first')!.attempts, 1);
    expect(HiveBoxes.llmProblems.get('default_next')!.attempts, 1);
    expect(HiveBoxes.userStats.get('default_stats')!.mathTotalProblems, 2);
    expect(HiveBoxes.userStats.get('default_stats')!.mathTotalCorrect, 2);
    await _closePractice(tester);
  });

  testWidgets('题组再练保持题数并换掉整组，未做题先于已做题', (tester) async {
    final first = _problem(id: 'first', questionText: '原题一', answer: 8);
    final second = _problem(id: 'second', questionText: '原题二', answer: 7);
    final next = _problem(id: 'next', questionText: '未做题', answer: 6);
    final old = _problem(
      id: 'old',
      questionText: '较新的已做题',
      answer: 5,
      done: true,
      createdAt: DateTime(2026, 10, 2),
    );
    final extra = _problem(
      id: 'extra',
      questionText: '较早的已做题',
      answer: 4,
      done: true,
      createdAt: DateTime(2026, 9, 1),
    );
    await _startPractice(
      tester,
      current: [first, second],
      library: [first, second, next, old, extra],
    );
    await _finishRound(tester, [8, 7]);
    await tester.runAsync(() => tester.tap(find.text('再练一组')));
    await _waitUntil(
      tester,
      () => PracticeDraftRepository().get('word') != null,
    );
    final draft = PracticeDraftRepository().get('word')!;
    expect((draft['problems'] as List).map((p) => p['id']), [next.id, old.id]);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text(next.questionText), findsOneWidget);
    await _closePractice(tester);
  });

  testWidgets('同类题不足原题数时只练剩余题，不用原题补足', (tester) async {
    final first = _problem(id: 'first', questionText: '原题一', answer: 8);
    final second = _problem(id: 'second', questionText: '原题二', answer: 7);
    final next = _problem(id: 'next', questionText: '剩余题', answer: 6);
    await _startPractice(
      tester,
      current: [first, second],
      library: [first, second, next],
    );
    await _finishRound(tester, [8, 7]);
    await tester.runAsync(() => tester.tap(find.text('再练一组')));
    await _waitUntil(
      tester,
      () => PracticeDraftRepository().get('word') != null,
    );
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text(next.questionText), findsOneWidget);
    expect(
      (PracticeDraftRepository().get('word')!['problems'] as List).length,
      1,
    );
    await _closePractice(tester);
  });

  testWidgets('没有其他同类题时返回题库并提示，不重建原题草稿', (tester) async {
    final first = _problem(id: 'first', questionText: '唯一题目', answer: 8);
    await _startPractice(tester, current: [first], library: [first]);
    await _finishRound(tester, [8]);
    await tester.runAsync(() => tester.tap(find.text('再练一组')));
    await _waitUntil(tester, () => find.text('返回应用题题库').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('同类题目已练完，可以在题库选择其他题目或生成新题'), findsOneWidget);
    expect(find.text(first.questionText), findsNothing);
    expect(PracticeDraftRepository().get('word'), isNull);
    expect(HiveBoxes.mathSessions.length, 1);
    expect(HiveBoxes.llmProblems.get('default_first')!.attempts, 1);
    await _closePractice(tester);
  });

  testWidgets('答对判定正确并记录做题状态', (tester) async {
    final problems = [
      _problem(id: 'p1', questionText: '小明有 12 个苹果，吃了 4 个，还剩几个？', answer: 8),
    ];
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
      // recordAttempt 从 box 读取题目，需预先入库。
      await HiveBoxes.llmProblems.put('default_p1', problems.first);
    });
    await tester.runAsync(() async {
      await tester
          .pumpWidget(_wrap(WordProblemPracticePage(problems: problems)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('12 个苹果'), findsOneWidget);

    // 输入 8 → 正确
    await _answer(tester, '8');
    expect(find.text('回答正确！'), findsOneWidget);

    final stored = HiveBoxes.llmProblems.get('default_p1');
    expect(stored, isNotNull);
    expect(stored!.done, isTrue);
    expect(stored.attempts, equals(1));
    expect(stored.correctCount, equals(1));
    expect(stored.lastDoneAt, isNotNull);

    // 无错题
    expect(HiveBoxes.mathMistakes.isEmpty, isTrue);

    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  });

  testWidgets('答错显示正确答案与讲解并写入错题本', (tester) async {
    final problems = [
      _problem(id: 'p1', questionText: '小明有 12 个苹果，吃了 4 个，还剩几个？', answer: 8),
    ];
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
      await HiveBoxes.llmProblems.put('default_p1', problems.first);
    });
    await tester.runAsync(() async {
      await tester
          .pumpWidget(_wrap(WordProblemPracticePage(problems: problems)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await _answer(tester, '9');

    expect(find.text('再想想'), findsOneWidget);
    expect(find.text('正确答案：8个'), findsOneWidget);
    expect(find.text('查看讲解'), findsOneWidget);

    final mistake = HiveBoxes.mathMistakes.values.single;
    expect(mistake.problemType, equals('llm_word_problem'));
    expect(mistake.errorType, isNull);
    expect(mistake.correctAnswer, equals('8'));
    expect(mistake.userAnswer, equals('9'));
    expect(mistake.problemText, contains('苹果'));
    expect(mistake.solutionStepsJson, contains('减法'));

    final stored = HiveBoxes.llmProblems.get('default_p1');
    expect(stored!.done, isTrue);
    expect(stored.correctCount, equals(0));

    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  });

  testWidgets('完成全部题目后结算写入 llm_word_problem 会话', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
    });
    final problems = [
      _problem(id: 'p1', questionText: '小明有 12 个苹果，吃了 4 个，还剩几个？', answer: 8),
      _problem(
        id: 'p2',
        questionText: '花园里有 9 只蝴蝶，飞走 2 只，还剩几只？',
        answer: 7,
        operands: const [9, 2],
      ),
    ];
    await tester.runAsync(() async {
      await tester
          .pumpWidget(_wrap(WordProblemPracticePage(problems: problems)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 第 1 题答对
    await _answer(tester, '8');
    // 逐题持久化已写 MathSession（同 ID 覆盖）
    expect(HiveBoxes.mathSessions.length, equals(1));
    expect(
      HiveBoxes.mathSessions.values.single.problemType,
      equals('llm_word_problem'),
    );

    // 第 2 题答对后查看成绩 → 结算
    await tester.runAsync(() async {
      await tester.tap(find.text('下一题'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _answer(tester, '7');
    // 结算链（save/activity/stars/checkIn 多个真实写入）在真实区完成。
    await tester.runAsync(() async {
      await tester.tap(find.text('查看成绩'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final session = HiveBoxes.mathSessions.values.single;
    expect(session.problemType, equals('llm_word_problem'));
    expect(session.totalProblems, equals(2));
    expect(session.correctCount, equals(2));
    expect(session.problemsJson, contains('苹果'));
    expect(session.problemsJson, contains('蝴蝶'));

    // userStats 增量已累计
    final stats = HiveBoxes.userStats.get('default_stats');
    expect(stats!.mathTotalProblems, equals(2));
    expect(stats.mathTotalCorrect, equals(2));

    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  });

  testWidgets('结算失败可重试，重复点击不重复累计或奖励', (tester) async {
    final problem = _problem(id: 'retry', questionText: '还剩几个苹果？', answer: 8);
    final sessions = _FailFinalSessionOnce();
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
      await tester.pumpWidget(
        _wrap(
          WordProblemPracticePage(problems: [problem]),
          sessions: sessions,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await _answer(tester, '8');
    await tester.runAsync(() async {
      await tester.tap(find.text('查看成绩'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('答题进度或结算保存失败，请重试'), findsOneWidget);
    expect(HiveBoxes.mathSessions.values.single.starsEarned, 0);
    expect(
      HiveBoxes.meta.keys
          .any((key) => key.toString().contains('practice_draft:word')),
      isTrue,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('查看成绩'));
      // 同一帧连点被同步转移锁拦住。
      await tester.tap(find.text('查看成绩'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final stats = HiveBoxes.userStats.get('default_stats')!;
    expect(stats.mathTotalProblems, 1);
    expect(stats.totalStars, HiveBoxes.mathSessions.values.single.starsEarned);
    expect(HiveBoxes.learningActivities.length, 1);
    expect(
      HiveBoxes.meta.keys
          .any((key) => key.toString().contains('practice_draft:word')),
      isFalse,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(seconds: 5));
  });
  testWidgets('恢复待结算草稿后保存失败，保留当前结果和重试入口', (tester) async {
    final problem =
        _problem(id: 'resume-retry', questionText: '还剩几个苹果？', answer: 8);
    final sessions = _FailFinalSessionOnce();
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
      await PracticeDraftRepository().save('word', {
        'sessionId': 'pending-word-final',
        'startedAt': DateTime(2026, 10, 16, 10).toIso8601String(),
        'completedAt': DateTime(2026, 10, 16, 10, 1).toIso8601String(),
        'elapsedMilliseconds': 60000,
        'index': 0,
        'input': '8',
        'problems': [problem.toSnapshot()],
        'records': [
          const ProblemRecord(
            problemText: '还剩几个苹果？',
            answerText: '8个',
            userAnswer: '8',
            isCorrect: true,
          ).toJson(),
        ],
      });
      await tester.pumpWidget(
        _wrap(
          const WordProblemPracticePage(problems: [], resume: true),
          sessions: sessions,
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
    expect(HiveBoxes.mathSessions.values.single.durationSeconds, 60);
    expect(
      HiveBoxes.mathSessions.values.single.finishedAt,
      DateTime(2026, 10, 16, 10, 1),
    );
    expect(HiveBoxes.learningActivities.length, 1);
    expect(HiveBoxes.userStats.get('default_stats')!.mathTotalProblems, 1);
    expect(PracticeDraftRepository().get('word'), isNull);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump(const Duration(seconds: 5));
  });
}
