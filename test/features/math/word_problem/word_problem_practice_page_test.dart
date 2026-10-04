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

import 'package:poemath/core/services/haptic_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
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
}) {
  return LlmProblem(
    id: id,
    profileId: 'default',
    questionText: questionText,
    unit: '个',
    operands: operands,
    operators: operators,
    answer: answer,
    explanation: '讲解：用减法计算。',
    batchId: 'batch_1',
    createdAt: DateTime(2026, 10, 1),
    grade: 2,
    semester: '上',
    topic: 'subtraction',
    difficulty: 2,
  );
}

Widget _wrap(Widget child) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
    ],
  );
  return ProviderScope(
    overrides: [
      hapticServiceProvider.overrideWithValue(_NoopHapticService()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// 输入答案并提交。提交触发的写入链放入真实异步区完成。
Future<void> _answer(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.runAsync(() async {
    await tester.tap(find.byIcon(Icons.check_rounded));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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
    await tester.pumpWidget(
      _wrap(WordProblemPracticePage(problems: problems)),
    );
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

    await tester.pumpWidget(const SizedBox.shrink());
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
    await tester.pumpWidget(
      _wrap(WordProblemPracticePage(problems: problems)),
    );
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

    await tester.pumpWidget(const SizedBox.shrink());
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
    await tester.pumpWidget(
      _wrap(WordProblemPracticePage(problems: problems)),
    );
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
    await tester.tap(find.text('下一题'));
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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
