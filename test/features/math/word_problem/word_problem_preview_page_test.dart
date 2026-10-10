// test/features/math/word_problem/word_problem_preview_page_test.dart
//
// 预览页 widget 测试：勾选/取消与入库数量一致、丢弃题不入库且显示原因。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';
import 'package:poemath/features/math/word_problem/word_problem_preview_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../../helpers/hive_test_helper.dart';

/// addAll 恒抛异常的假仓储（模拟磁盘满/Box 损坏），W2 防护测试注入。
class _FailingLlmProblemRepository extends LlmProblemRepository {
  @override
  Future<void> addAll(List<LlmProblem> problems) async {
    throw Exception('disk full');
  }
}

ProblemSkeleton _skeleton({
  List<int> operands = const [12, 4],
  List<Operator> operators = const [Operator.subtract],
  int answer = 8,
}) {
  return ProblemSkeleton(
    operands: operands,
    operators: operators,
    answer: answer,
    unitHint: '个',
    difficulty: 2,
  );
}

WordProblemPreviewData _previewData(List<WordProblemPreviewItem> items) {
  return WordProblemPreviewData(
    grade: 2,
    semester: '上',
    topicName: 'subtraction',
    items: items,
  );
}

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => child,
      ),
      GoRoute(
        path: '/word-problem/library',
        builder: (_, __) => const Scaffold(body: SizedBox()),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
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

  testWidgets('通过项默认全选，取消一项后入库数量减少', (tester) async {
    final items = [
      WordProblemPreviewItem(
        skeleton: _skeleton(),
        draft: const LlmWordProblemDraft(
          index: 1,
          text: '小明有 12 个苹果，吃了 4 个，还剩几个？',
          unit: '个',
          explanation: '12 - 4 = 8',
        ),
        rejectReason: null,
      ),
      WordProblemPreviewItem(
        skeleton: _skeleton(operands: const [5, 3], answer: 8),
        draft: const LlmWordProblemDraft(
          index: 2,
          text: '花园里有 5 朵红花和 3 朵黄花，一共有几朵花？',
          unit: '朵',
          explanation: '5 + 3 = 8',
        ),
        rejectReason: null,
      ),
    ];

    await tester.pumpWidget(
      _wrap(WordProblemPreviewPage(data: _previewData(items))),
    );
    await tester.pumpAndSettle();

    // 概要统计文案已移除（家长自行看列表勾选）
    expect(find.textContaining('通过校验'), findsNothing);
    // 确认按钮在 AppBar 右上角，宽屏（测试默认 800x600）显示图标+文案
    expect(find.text('确认入库 2 题'), findsOneWidget);

    // 取消第一题（勾选框现靠右）
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('确认入库 1 题'), findsOneWidget);

    // 确认入库：addAll 的真实 Hive 写入须在真实异步区完成
    //（FakeAsync 区 flush 永不完成，会冻结后续导航与 tearDown）。
    await tester.runAsync(() async {
      await tester.tap(find.text('确认入库 1 题'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(HiveBoxes.llmProblems.length, equals(1));
    final stored = HiveBoxes.llmProblems.values.single;
    expect(stored.questionText, contains('红花'));
    expect(stored.topic, equals('subtraction'));
    expect(stored.profileId, isNotEmpty);
    expect(stored.done, isFalse);
  });

  testWidgets('丢弃题显示违规原因且不入库', (tester) async {
    final items = [
      WordProblemPreviewItem(
        skeleton: _skeleton(),
        draft: const LlmWordProblemDraft(
          index: 1,
          text: '小明有 12 个苹果，吃了 4 个，还剩几个？',
          unit: '个',
          explanation: '12 - 4 = 8',
        ),
        rejectReason: null,
      ),
      WordProblemPreviewItem(
        skeleton: _skeleton(operands: const [6, 2], answer: 4),
        draft: const LlmWordProblemDraft(
          index: 2,
          text: '商店有 6 箱牛奶，卖出 2 箱，还剩几箱？',
          unit: '个',
          explanation: '',
        ),
        rejectReason: '单位与骨架不一致：应为「个」，实际「个」',
      ),
    ];

    await tester.pumpWidget(
      _wrap(WordProblemPreviewPage(data: _previewData(items))),
    );
    await tester.pumpAndSettle();

    // 概要统计文案已移除，丢弃信息只体现在列表卡片上
    //（「丢弃原因：」在卡片内属预期展示，概要的「丢弃 N 题」不得再出现）。
    expect(find.textContaining('丢弃 '), findsNothing);
    expect(find.text('已丢弃'), findsOneWidget);
    expect(find.textContaining('单位与骨架不一致'), findsOneWidget);
    // 丢弃题无勾选框
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('确认入库 1 题'), findsOneWidget);

    // 确认后仅 1 题入库（真实写入在真实异步区完成）
    await tester.runAsync(() async {
      await tester.tap(find.text('确认入库 1 题'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(HiveBoxes.llmProblems.length, equals(1));
    expect(
      HiveBoxes.llmProblems.values.single.questionText,
      contains('苹果'),
    );
  });

  testWidgets('batchId 使用微秒时间戳，连续两批入库不同', (tester) async {
    // 同一测试内两次入库：第一次确认后页面替换为题库页，
    // 经 router 重新进入预览页再入一批，比对两批 batchId。
    final item = WordProblemPreviewItem(
      skeleton: _skeleton(),
      draft: const LlmWordProblemDraft(
        index: 1,
        text: '小明有 12 个苹果，吃了 4 个，还剩几个？',
        unit: '个',
        explanation: '',
      ),
      rejectReason: null,
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => WordProblemPreviewPage(
            data: _previewData([item]),
          ),
        ),
        GoRoute(
          path: '/word-problem/library',
          builder: (_, __) => const Scaffold(body: SizedBox()),
        ),
      ],
    );

    Future<void> confirmOnce() async {
      await tester.runAsync(() async {
        await tester.tap(find.text('确认入库 1 题'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    // 第一批入库
    await confirmOnce();
    final firstBatch = HiveBoxes.llmProblems.values.single.batchId;

    // 重新进入预览页，第二批入库
    //（router.push 返回的 Future 在路由 pop 时才 resolve，不可 await）。
    unawaited(router.push('/'));
    await tester.pumpAndSettle();
    // 第一批的「已入库」SnackBar（默认 4 秒）覆盖底部按钮且其定时器
    // 不产生帧、pumpAndSettle 不会等它：推进时间让 SnackBar 退场。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await confirmOnce();
    expect(HiveBoxes.llmProblems.length, equals(2));
    final secondBatch = HiveBoxes.llmProblems.values.last.batchId;

    // 微秒时间戳（2026 年为 16 位数字；毫秒仅 13 位），两批必然不同。
    expect(RegExp(r'^\d{16}$').hasMatch(firstBatch), isTrue);
    expect(RegExp(r'^\d{16}$').hasMatch(secondBatch), isTrue);
    expect(secondBatch, isNot(firstBatch));
  });

  testWidgets('addAll 失败时提示入库失败、按钮恢复可点击（W2）', (tester) async {
    final item = WordProblemPreviewItem(
      skeleton: _skeleton(),
      draft: const LlmWordProblemDraft(
        index: 1,
        text: '小明有 12 个苹果，吃了 4 个，还剩几个？',
        unit: '个',
        explanation: '',
      ),
      rejectReason: null,
    );

    // 注入 addAll 恒抛异常的假仓储：交互链在微任务内完成，
    // 无真实 Hive 写入，不需要 runAsync。
    await tester.pumpWidget(
      _wrap(
        WordProblemPreviewPage(data: _previewData([item])),
        overrides: [
          llmProblemRepositoryProvider.overrideWithValue(
            _FailingLlmProblemRepository(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认入库 1 题'));
    await tester.pump();

    // 失败提示出现，异常被 _confirm 捕获（不成为 unhandled exception）
    expect(find.text('入库失败，请重试'), findsOneWidget);
    // 未导航离开预览页，Hive 零写入
    expect(find.text('家长预览'), findsOneWidget);
    expect(HiveBoxes.llmProblems, isEmpty);
    // _saving 已恢复：AppBar 右上角确认按钮重新可点击
    final button = tester.widget<TextButton>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNotNull);

    // SnackBar 退场：4 秒定时器从前向动画完成那一帧才起算，一帧大步
    // 跳变会让定时器晚启动——先推进 1 秒让入场动画完成、再推进 5 秒
    // 覆盖定时器与退出动画，最后 settle 清掉移除帧，按钮不再被遮挡。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('入库失败，请重试'), findsNothing);

    // 第二次点击：可重试，异常再次被吞
    await tester.tap(find.text('确认入库 1 题'));
    await tester.pump();
    expect(find.text('入库失败，请重试'), findsOneWidget);
    expect(HiveBoxes.llmProblems, isEmpty);
  });
}
