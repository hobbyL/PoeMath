import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/math_mistake_detail_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/word_problem/word_problem_library_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

enum _Deletion {
  problem('应用题单题', '删除该题'),
  batch('应用题批次', '删除该批次'),
  all('应用题清空', '清空题库'),
  mistake('错题', '删除错题');

  const _Deletion(this.label, this.title);
  final String label;
  final String title;

  Finder get entry => switch (this) {
        problem => find.byTooltip('删除此题').first,
        batch => find.byTooltip('删除该批次'),
        all => find.widgetWithText(OutlinedButton, '清空'),
        mistake => find.widgetWithText(TextButton, '删除'),
      };

  Finder get confirmation => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(this == all ? '清空' : '删除'),
      );
}

class _MemoryProblems extends LlmProblemRepository {
  _MemoryProblems()
      : items = [
          for (final id in ['p1', 'p2'])
            LlmProblem(
              id: id,
              profileId: 'default',
              questionText: '小明有12个苹果，又买4个，一共有几个？',
              unit: '个',
              operands: const [12, 4],
              operators: const ['+'],
              answer: 16,
              explanation: '',
              batchId: 'batch',
              createdAt: DateTime(2026, 10, 1),
              grade: 2,
              semester: '上',
              topic: 'addition',
              difficulty: 1,
            ),
        ];

  final List<LlmProblem> items;
  bool failDelete = false;

  @override
  List<LlmProblem> getAll() => items
      .where((problem) => problem.profileId == ProfileScope.currentId)
      .toList();

  @override
  Future<void> delete(String id, {void Function()? authorize}) async {
    authorize?.call();
    ParentAccessService.instance.assertAllowed();
    if (failDelete) throw StateError('synthetic storage failure');
    items.removeWhere((problem) => problem.id == id);
  }
}

class _MemoryMistakes extends MathMistakeRepository {
  final items = [
    MathMistake(
      id: 'm1',
      profileId: 'default',
      problemText: '25 + 38 = ?',
      correctAnswer: '63',
      userAnswer: '61',
      problemType: 'addition',
      grade: 2,
    ),
  ];
  bool failDelete = false;

  @override
  List<MathMistake> getAll() => List.of(items);

  @override
  MathMistake? getById(String id) {
    for (final mistake in items) {
      if (mistake.id == id) return mistake;
    }
    return null;
  }

  @override
  Future<void> delete(String id, {void Function()? authorize}) async {
    authorize?.call();
    ParentAccessService.instance.assertAllowed();
    if (failDelete) throw StateError('synthetic storage failure');
    items.removeWhere((mistake) => mistake.id == id);
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  }
  expect(ready(), isTrue, reason: '等待页面操作完成');
  await tester.runAsync(() => tester.pump(const Duration(milliseconds: 300)));
}

/// 弹窗由真实异步验证发起，关闭和后续写入也须推动真实区中的帧。
Future<void> _drainFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final access = ParentAccessService.instance;
  late _MemoryProblems problems;
  late _MemoryMistakes mistakes;
  late GoRouter router;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    FlutterSecureStorage.setMockInitialValues({});
    access.didChangeAppLifecycleState(AppLifecycleState.resumed);
    access.lock();
    problems = _MemoryProblems();
    mistakes = _MemoryMistakes();
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('测试首页')),
        ),
        GoRoute(
          path: '/library',
          builder: (_, __) => const WordProblemLibraryPage(),
        ),
        GoRoute(
          path: '/mistake',
          builder: (_, __) => const MathMistakeDetailPage(mistakeId: 'm1'),
        ),
        GoRoute(
          path: AppRoutes.parentProtection,
          builder: (context, _) => Scaffold(
            appBar: AppBar(title: const Text('家长设置占位')),
            body: TextButton(
              onPressed: () => context.pop(),
              child: const Text('返回学习'),
            ),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    access.lock();
    access.didChangeAppLifecycleState(AppLifecycleState.resumed);
    ProfileScope.reset();
    router.dispose();
    await tearDownHiveForTesting();
  });

  Future<void> mount(WidgetTester tester, _Deletion deletion) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => tester.pumpWidget(
        ProviderScope(
          overrides: [
            llmProblemRepositoryProvider.overrideWithValue(problems),
            mathMistakeRepoProvider.overrideWithValue(mistakes),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    // 原页面保留在栈中，错题删除成功后正常返回。
    router.push<void>(deletion == _Deletion.mistake ? '/mistake' : '/library');
    await _drainFrames(tester);
  }

  Future<void> open(WidgetTester tester, _Deletion deletion) async {
    await tester.runAsync(() => tester.tap(deletion.entry));
    await _pumpUntil(
      tester,
      () =>
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.text('家长设置占位').evaluate().isNotEmpty,
    );
  }

  void expectUnchanged() {
    expect(problems.items, hasLength(2));
    expect(mistakes.items, hasLength(1));
  }

  for (final deletion in _Deletion.values) {
    testWidgets('${deletion.label}有效授权时确认删除，直接复用解锁窗口', (tester) async {
      await tester.runAsync(unlockParentForTesting);
      await mount(tester, deletion);
      await open(tester, deletion);
      expect(find.text('家长解锁'), findsNothing);
      expect(find.text(deletion.title), findsOneWidget);
      await tester.tap(deletion.confirmation);
      await _drainFrames(tester);
      expect(
        problems.items,
        hasLength(
          switch (deletion) {
            _Deletion.problem => 1,
            _Deletion.mistake => 2,
            _ => 0,
          },
        ),
      );
      expect(mistakes.items, hasLength(deletion == _Deletion.mistake ? 0 : 1));
      if (deletion == _Deletion.mistake) {
        expect(find.text('测试首页'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('${deletion.label}未设置 PIN 跳设置，返回后不自动删除', (tester) async {
      await mount(tester, deletion);
      await open(tester, deletion);
      expect(find.text('家长设置占位'), findsOneWidget);
      expect(find.text(deletion.title), findsNothing);
      expectUnchanged();
      await tester.runAsync(unlockParentForTesting);
      await tester.tap(find.text('返回学习'));
      await _drainFrames(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expectUnchanged();
      await open(tester, deletion);
      expect(find.text(deletion.title), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _drainFrames(tester);
      expectUnchanged();
    });

    testWidgets('${deletion.label}锁定时先输入 PIN，取消不删除', (tester) async {
      await tester.runAsync(unlockParentForTesting);
      access.lock();
      await mount(tester, deletion);
      await open(tester, deletion);
      expect(find.text('家长解锁'), findsOneWidget);
      expect(find.text(deletion.title), findsNothing);
      await tester.tap(find.text('取消'));
      await _drainFrames(tester);
      expectUnchanged();
      expect(access.isUnlocked, isFalse);
    });

    for (final invalidate in ['锁定', '后台', '切换档案']) {
      testWidgets('${deletion.label}确认期间$invalidate 后不删除', (tester) async {
        await tester.runAsync(unlockParentForTesting);
        await mount(tester, deletion);
        await open(tester, deletion);
        expect(find.text(deletion.title), findsOneWidget);
        switch (invalidate) {
          case '锁定':
            access.lock();
          case '后台':
            binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          case '切换档案':
            ProfileScope.switchTo('other');
        }
        await tester.tap(deletion.confirmation);
        await _drainFrames(tester);
        expectUnchanged();
        expect(find.text('家长验证已失效，删除已停止，请重新验证'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('错误 PIN 保留题目，正确 PIN 后确认；5 分钟内批次删除复用验证', (tester) async {
    await tester.runAsync(unlockParentForTesting);
    access.lock();
    await mount(tester, _Deletion.problem);
    await open(tester, _Deletion.problem);
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      '000000',
    );
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '解锁')),
    );
    await _pumpUntil(tester, () => find.text('PIN 不正确').evaluate().isNotEmpty);
    expectUnchanged();
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      testParentPin,
    );
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '解锁')),
    );
    await _pumpUntil(tester, () => find.text('删除该题').evaluate().isNotEmpty);
    expect(access.isUnlocked, isTrue);
    expectUnchanged();
    await tester.tap(find.text('取消'));
    await _drainFrames(tester);
    await open(tester, _Deletion.batch);
    expect(find.text('家长解锁'), findsNothing);
    expect(find.text('删除该批次'), findsOneWidget);
    await tester.tap(_Deletion.batch.confirmation);
    await _drainFrames(tester);
    expect(problems.items, isEmpty);
    expect(mistakes.items, hasLength(1));
  });

  for (final deletion in [_Deletion.problem, _Deletion.mistake]) {
    testWidgets('${deletion.label}确认后离开页面，不删除也不访问已销毁页面', (tester) async {
      await tester.runAsync(unlockParentForTesting);
      await mount(tester, deletion);
      await open(tester, deletion);
      // 同一帧内确认并导航，等待弹窗返回的旧操作必须被拒绝。
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: deletion.confirmation,
          matching:
              find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        ),
      );
      button.onPressed!();
      router.go('/');
      await _drainFrames(tester);
      expect(find.text('测试首页'), findsOneWidget);
      expectUnchanged();
      expect(tester.takeException(), isNull);
    });

    testWidgets('${deletion.label}写入失败时提示并保留数据，可重新点击', (tester) async {
      await tester.runAsync(unlockParentForTesting);
      problems.failDelete = true;
      mistakes.failDelete = true;
      await mount(tester, deletion);
      await open(tester, deletion);
      await tester.tap(deletion.confirmation);
      await _drainFrames(tester);
      expectUnchanged();
      expect(
        find.text(deletion == _Deletion.mistake ? '删除错题失败，请重试' : '删除未完成，请重试'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await open(tester, deletion);
      expect(find.text(deletion.title), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _drainFrames(tester);
    });
  }

  testWidgets('连续点击删除只打开一个验证弹窗', (tester) async {
    await tester.runAsync(unlockParentForTesting);
    access.lock();
    await mount(tester, _Deletion.problem);
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: _Deletion.problem.entry,
        matching: find.byType(IconButton),
      ),
    );
    await tester.runAsync(() async {
      button.onPressed!();
      button.onPressed!();
    });
    await _pumpUntil(tester, () => find.text('家长解锁').evaluate().isNotEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _drainFrames(tester);
    expectUnchanged();
    await open(tester, _Deletion.problem);
    expect(find.text('家长解锁'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _drainFrames(tester);
  });

  testWidgets('未设置 PIN 仍可查看错题并打开原题回练', (tester) async {
    await mount(tester, _Deletion.mistake);
    expect(find.text('错题详情'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '再练一次'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('家长解锁'), findsNothing);
    expect(find.text('家长设置占位'), findsNothing);
    expectUnchanged();
    await tester.tap(find.text('取消'));
    await _drainFrames(tester);
  });
}
