// test/features/math/word_problem/word_problem_library_page_test.dart
//
// 题库管理页 widget 测试：空态引导、统计、筛选、删除。
// 说明：testWidgets 处于 FakeAsync 区，真实 Hive 落盘永不完成，
// 页面交互链会冻结在 await 上。故按 poem_quiz_page_test 先例，
// 以内存 repository override 驱动页面（Hive 真实行为由
// llm_problem_repository_test.dart 覆盖）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';
import 'package:poemath/features/math/word_problem/word_problem_library_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';

import '../../../helpers/hive_test_helper.dart';

/// 内存实现：删除即时完成，getAll/stats 继承基类（基于 getAll）。
class _MemoryLlmProblemRepository extends LlmProblemRepository {
  final Map<String, LlmProblem> store = {};

  @override
  List<LlmProblem> getAll() {
    return store.values
        .where((p) => p.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> delete(String id) async {
    store.remove(ProfileScope.key(id));
  }
}

LlmProblem _problem({
  required String id,
  required String questionText,
  String topic = 'subtraction',
  bool done = false,
  int attempts = 0,
  int correctCount = 0,
}) {
  return LlmProblem(
    id: id,
    profileId: 'default',
    questionText: questionText,
    unit: '个',
    operands: const [12, 4],
    operators: const ['-'],
    answer: 8,
    explanation: '',
    batchId: 'batch_1',
    createdAt: DateTime(2026, 10, 1),
    grade: 2,
    semester: '上',
    topic: topic,
    difficulty: 2,
    done: done,
    attempts: attempts,
    correctCount: correctCount,
    lastDoneAt: done ? DateTime(2026, 10, 2) : null,
  );
}

Widget _wrap(_MemoryLlmProblemRepository repo) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const WordProblemLibraryPage()),
      GoRoute(
        path: '/word-problem/generate',
        builder: (_, __) => const Scaffold(body: SizedBox()),
      ),
      GoRoute(
        path: '/word-problem/practice',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('练习占位')),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [llmProblemRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('空题库显示引导态', (tester) async {
    await tester.pumpWidget(_wrap(_MemoryLlmProblemRepository()));
    await tester.pumpAndSettle();

    expect(find.text('题库还是空的'), findsOneWidget);
    expect(find.text('去生成'), findsOneWidget);
  });

  testWidgets('显示统计与批次分组，筛选未做后仅显示未做题', (tester) async {
    final repo = _MemoryLlmProblemRepository()
      ..store['default_p1'] = _problem(
        id: 'p1',
        questionText: '小明有 12 个苹果，吃了 4 个，还剩几个？',
        done: true,
        attempts: 2,
        correctCount: 1,
      )
      ..store['default_p2'] = _problem(
        id: 'p2',
        questionText: '花园里有 9 只蝴蝶，飞走 2 只，还剩几只？',
      );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // 统计卡（总题数 / 已做 / 正确率）
    expect(find.text('总题数'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    // 筛选已移入弹窗，正文仅统计卡含「已做」标签
    expect(find.text('已做'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);

    // 批次头显示真实题数与无歧义日期（修复「10/10」误读为题数）
    expect(find.textContaining('共 2 题'), findsOneWidget);
    expect(find.textContaining('10月1日'), findsOneWidget);

    // 两题均在列表
    expect(find.textContaining('苹果'), findsOneWidget);
    expect(find.textContaining('蝴蝶'), findsOneWidget);
    expect(find.textContaining('已做 2 次'), findsOneWidget);
    // 未做题副标题现仅为「未做」
    expect(find.text('未做'), findsOneWidget);

    // 打开筛选弹窗 → 选「未做」→ 完成关闭
    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    // 弹窗内「未做」为 FilterChip（正文行副标题亦含「未做」，故按类型定位）
    await tester.tap(find.widgetWithText(FilterChip, '未做'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('蝴蝶'), findsOneWidget);
    expect(find.textContaining('苹果'), findsNothing);
  });

  testWidgets('点击题目行跳转练习页（不再弹删除确认）', (tester) async {
    final repo = _MemoryLlmProblemRepository()
      ..store['default_p1'] = _problem(
        id: 'p1',
        questionText: '小明有 12 个苹果，吃了 4 个，还剩几个？',
      );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('苹果'));
    await tester.pumpAndSettle();

    // 行点击进入练习页，而非弹出删除确认
    expect(find.text('练习占位'), findsOneWidget);
    expect(find.text('删除该题'), findsNothing);
  });

  testWidgets('点击单题删除按钮弹确认并删除该题', (tester) async {
    final repo = _MemoryLlmProblemRepository()
      ..store['default_p1'] = _problem(
        id: 'p1',
        questionText: '小明有 12 个苹果，吃了 4 个，还剩几个？',
      );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // 行尾独立删除按钮（与「删除该批次」同图标，按 tooltip 区分）
    await tester.tap(find.byTooltip('删除此题'));
    await tester.pumpAndSettle();

    expect(find.text('删除该题'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repo.store.isEmpty, isTrue);
    expect(find.text('题库还是空的'), findsOneWidget);
  });

  testWidgets('清空题库需二次确认', (tester) async {
    final repo = _MemoryLlmProblemRepository()
      ..store['default_p1'] = _problem(
        id: 'p1',
        questionText: '小明有 12 个苹果，吃了 4 个，还剩几个？',
      );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    // 取消不删除
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.store.length, equals(1));

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    // 对话框内确认按钮（页面上还有一个「清空」）。
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();
    expect(repo.store.isEmpty, isTrue);
  });
}
