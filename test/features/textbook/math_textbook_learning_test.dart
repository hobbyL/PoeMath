import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/data/repositories/math_textbook_learning_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
import 'package:poemath/features/textbook/math_textbook_learning_editor_page.dart';
import 'package:poemath/features/textbook/math_textbook_lesson_page.dart';
import 'package:poemath/features/textbook/math_textbook_practice_page.dart';
import 'package:poemath/features/textbook/math_textbook_study_page.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';
import '../../helpers/parent_access_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  defineMathTextbookLearningTests();
}

void defineMathTextbookLearningTests({
  Future<void> Function(WidgetTester tester, String name)? capture,
}) {
  final book = mathTextbookFixture();
  late Directory directory;
  late MathTextbookCourseRepository courses;
  late TextbookRepository books;
  late MathTextbookLesson lesson;
  GoRouter? router;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory = await Directory.systemTemp.createTemp('math-learning-ui-');
    courses = MathTextbookCourseRepository(
      directoryProvider: () async => directory,
    );
    books = TextbookRepository();
    await books.addIfAbsent(book);
  });

  tearDown(() async {
    router?.dispose();
    router = null;
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
    await directory.delete(recursive: true);
  });

  Future<void> install(MathTextbookLesson value, {bool approve = true}) async {
    final generated = await courses.saveGenerated(
      book,
      value,
      generation: courses.generation(book.pdfSha256),
      authorize: () {},
    );
    lesson = approve
        ? value.approve(
            pdfSha256: book.pdfSha256,
            reviewer: '测试家长',
            editingMilliseconds: 1000,
          )
        : value;
    await courses.saveLesson(
      book,
      lesson,
      expectedRevision: generated.revision,
      generation: courses.generation(book.pdfSha256),
      authorize: () {},
    );
  }

  MathTextbookLearningRepository repository() => MathTextbookLearningRepository(
    book: book,
    courses: courses,
    findBook: books.find,
  );

  Future<void> waitFor(WidgetTester tester, bool Function() complete) async {
    final clock = Stopwatch()..start();
    do {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    } while (!complete() && clock.elapsed < const Duration(seconds: 8));
    expect(
      complete(),
      isTrue,
      reason:
          '等待页面操作完成，当前文字：${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' / ')}',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> mount(
    WidgetTester tester,
    String location, {
    Size size = const Size(420, 860),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(() async {
      await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pump();
      var drained = false;
      await tester.runAsync(() async {
        unawaited(courses.drain().whenComplete(() => drained = true));
      });
      await waitFor(tester, () => drained);
      await drainHiveWritesForTesting(tester);
    });
    router = createAppRouter(initialLocation: location);
    await tester.runAsync(
      () => tester.pumpWidget(
        ProviderScope(
          overrides: [
            textbookRepositoryProvider.overrideWithValue(books),
            mathTextbookRepositoryProvider.overrideWithValue(courses),
            textbookCatalogProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.resolve(
              subject: AppSubject.math,
              brightness: brightness,
            ),
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('math-textbook-evidence'),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<T> io<T>(WidgetTester tester, Future<T> Function() action) async {
    T? result;
    Object? failure;
    StackTrace? failureStack;
    var complete = false;
    await tester.runAsync(() async {
      unawaited(
        action().then(
          (value) {
            result = value;
            complete = true;
          },
          onError: (Object error, StackTrace stack) {
            failure = error;
            failureStack = stack;
            complete = true;
          },
        ),
      );
    });
    await waitFor(tester, () => complete);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    return result as T;
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await waitFor(tester, () => find.byType(Scrollable).evaluate().isNotEmpty);
    if (finder.evaluate().isEmpty) {
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      state.position.jumpTo(state.position.minScrollExtent);
      await tester.pump();
    }
    for (
      var attempt = 0;
      attempt < 45 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(
        (position.pixels + 180).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await visible(tester, finder);
    await tester.runAsync(() => tester.tap(finder));
    await tester.pump();
  }

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> enter(WidgetTester tester, String label, String text) async {
    await visible(tester, input(label));
    await tester.enterText(input(label), text);
  }

  testWidgets('未审课可阅读本课内容，未核对的自动答案仍不判分', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture(), approve: false));
    lockParentForTesting();
    await mount(
      tester,
      AppRoutes.mathTextbookStudyOf(book.pdfSha256, lesson.id),
    );
    await waitFor(tester, () => find.text('阅读本课内容').evaluate().isNotEmpty);
    expect(find.text('本课待家长核对'), findsNothing);
    await tap(tester, find.text('阅读本课内容'));
    await waitFor(
      tester,
      () => find
          .text('把2个圆和3个圆合在一起，共有5个圆。', findRichText: true)
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(TextField), findsNothing);
    router!.go(AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id));
    await waitFor(tester, () => find.text('本课练习暂不可用').evaluate().isNotEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(HiveBoxes.mathSessions.values, isEmpty);
  });

  for (final large in [false, true]) {
    testWidgets('未审核课时可保存已读并返回书目，纸上练习可进入（大字体：$large）', (tester) async {
      final source = mathLearningFixture(
        manual: true,
        kind: MathTextbookPracticeKind.parentTask,
      );
      await tester.runAsync(
        () => install(
          MathTextbookLesson.fromJson({
            ...source.toJson(),
            'learning': {
              ...source.learning!.toJson(),
              'coverageConfirmed': false,
              'exercises': [
                source.learning!.exercises.single.toJson(),
                {
                  ...mathLearningFixture().learning!.exercises.single.toJson(),
                  'id': 'unchecked-automatic',
                },
              ],
            },
          }),
          approve: false,
        ),
      );
      lockParentForTesting();
      await mount(
        tester,
        AppRoutes.mathTextbookStudyOf(book.pdfSha256, lesson.id),
        size: large ? const Size(320, 820) : const Size(360, 800),
        scale: large ? 2 : 1,
      );
      await waitFor(tester, () => find.text('阅读本课内容').evaluate().isNotEmpty);
      await visible(tester, find.text('看完本课，标记已读'));
      final offsetBeforeRead = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      await tester.runAsync(() => tester.tap(find.text('看完本课，标记已读')));
      await tester.pump();
      await waitFor(tester, () => find.text('本课已读').evaluate().isNotEmpty);
      final afterRead = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      if (large) {
        expect(offsetBeforeRead, greaterThan(0));
        expect(afterRead.pixels, greaterThan(0));
      }
      expect(find.text('本课已读').hitTestable(), findsOneWidget);
      expect((await io(tester, () => repository().load())).readLessons, {
        lesson.id: mathTextbookReadingDigest(lesson),
      });
      expect(
        (await io(tester, () => courses.load(book)))!.lessons.single.review,
        isNull,
      );
      router!.go(AppRoutes.mathTextbookBookOf(book.pdfSha256));
      await waitFor(
        tester,
        () => find.text('可学 1 课 · 已读 1 课 · 练习完成 0 课').evaluate().isNotEmpty,
      );
      await tap(tester, find.widgetWithText(AppTile, lesson.title));
      await waitFor(tester, () => find.text('阅读本课内容').evaluate().isNotEmpty);
      await tap(tester, find.text('教材原题'));
      await waitFor(tester, () => input('纸上完成情况').evaluate().isNotEmpty);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(input('你的答案'), findsNothing);
      expect(find.text('本课待家长核对'), findsNothing);
    });
  }

  testWidgets('整书量级课时列表加载与撤审刷新使用对应课程的汇总', (tester) async {
    await tester.runAsync(() => install(denseMathLearningFixture()));
    await mount(tester, AppRoutes.mathTextbookBookOf(book.pdfSha256));
    await waitFor(
      tester,
      () => find.text('可学 1 课 · 已读 0 课 · 练习完成 0 课').evaluate().isNotEmpty,
    );
    expect(find.text('请家长整理与审核'), findsNothing);
    await tester.runAsync(
      () => install(lesson.edit(title: '更新后的大课时'), approve: false),
    );
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp).first),
      listen: false,
    );
    scope.invalidate(mathTextbookCourseProvider(book.pdfSha256));
    await waitFor(tester, () => find.text('更新后的大课时').evaluate().isNotEmpty);
    expect(find.text('更新后的大课时'), findsOneWidget);
    expect(find.text('可学 1 课 · 已读 0 课 · 练习完成 0 课'), findsOneWidget);
    expect(find.text('未读\nPDF 第 1～2 页'), findsOneWidget);
  });

  testWidgets('320dp 双倍字号、深色与键盘下完成原题，返回显示持久进度', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture()));
    await mount(
      tester,
      AppRoutes.mathTextbookStudyOf(book.pdfSha256, lesson.id),
      size: const Size(320, 640),
      scale: 2,
      brightness: Brightness.dark,
    );
    await waitFor(tester, () => find.text(lesson.title).evaluate().isNotEmpty);
    await tap(tester, find.text('看完本课，标记已读'));
    await waitFor(tester, () {
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp).first),
        listen: false,
      );
      final progress = scope.read(mathTextbookProgressProvider(book.pdfSha256));
      return !progress.isLoading &&
          progress.valueOrNull?.readLessons.length == 1;
    });
    await visible(tester, find.text('本课已读'));
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(
      tester,
      () =>
          find.byType(MathTextbookPracticePage).evaluate().isNotEmpty &&
          input('你的答案').evaluate().isNotEmpty,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    await enter(tester, '你的答案', '5');
    await capture?.call(tester, 'narrow-keyboard');
    await tap(tester, find.text('核对答案'));
    await waitFor(tester, () => find.text('这项答对了').evaluate().isNotEmpty);
    expect(tester.widget<TextField>(input('你的答案')).enabled, isFalse);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tap(tester, find.text('完成本次练习'));
    await waitFor(tester, () => find.text('本次练习已完成').evaluate().isNotEmpty);
    expect(find.textContaining('自动核对通过 1/1 题'), findsOneWidget);
    expect(HiveBoxes.mathSessions.values, hasLength(1));
    await tap(tester, find.text('返回本课'));
    await waitFor(
      tester,
      () =>
          find.byType(MathTextbookStudyPage).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await visible(tester, find.textContaining('已通过 1 组'));
    final progress = await io(tester, () => repository().load());
    expect(progress.history, hasLength(1));
    expect(progress.readLessons, hasLength(1));
  });

  testWidgets('多空、单位、商余、选项和比较保留未交输入，恢复后统一核对', (tester) async {
    final base = mathLearningFixture();
    final group = MathTextbookExercise(
      id: 'multi',
      title: '自有多空题组',
      blockIds: ['exercise'],
      knowledgePointIds: ['kp'],
      fields: [
        MathTextbookAnswerField(
          id: 'length',
          label: '长度',
          rule: MathTextbookAnswerRule(
            kind: MathTextbookAnswerKind.number,
            expected: '1',
            unit: 'm',
            allowUnitConversion: true,
          ),
        ),
        MathTextbookAnswerField(
          id: 'division',
          label: '有余数除法',
          rule: MathTextbookAnswerRule(
            kind: MathTextbookAnswerKind.remainder,
            expected: '3…2',
            divisor: 5,
          ),
        ),
        MathTextbookAnswerField(
          id: 'choice',
          label: '选择所有合适的选项',
          rule: MathTextbookAnswerRule(
            kind: MathTextbookAnswerKind.choice,
            options: ['甲', '乙', '丙'],
            correctChoices: ['甲', '丙'],
          ),
        ),
        MathTextbookAnswerField(
          id: 'comparison',
          label: '比较两个数量',
          rule: MathTextbookAnswerRule(
            kind: MathTextbookAnswerKind.comparison,
            expected: '>',
          ),
        ),
      ],
    );
    final value = base.edit(
      learning: MathTextbookLearning.fromJson({
        ...base.learning!.toJson(),
        'exercises': [group.toJson()],
      }),
    );
    await tester.runAsync(() => install(value));
    await mount(
      tester,
      AppRoutes.mathTextbookStudyOf(book.pdfSha256, lesson.id),
    );
    await waitFor(tester, () => find.text('教材原题').evaluate().isNotEmpty);
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(tester, () => input('长度').evaluate().isNotEmpty);
    await enter(tester, '长度', '100厘米');
    await enter(tester, '商', '3');
    await tap(tester, find.text('核对答案'));
    await waitFor(
      tester,
      () => find.textContaining('请完成本题全部作答项').evaluate().isNotEmpty,
    );
    expect(HiveBoxes.mathSessions.values, isEmpty);
    await tester.runAsync(() => tester.tap(find.byTooltip('保存并返回')));
    await waitFor(
      tester,
      () => find.byType(MathTextbookStudyPage).evaluate().isNotEmpty,
    );
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(tester, () => input('长度').evaluate().isNotEmpty);
    expect(tester.widget<TextField>(input('长度')).controller!.text, '100厘米');
    await visible(tester, input('商'));
    expect(tester.widget<TextField>(input('商')).controller!.text, '3');
    await enter(tester, '余数', '2');
    for (final option in ['甲', '丙']) {
      await tap(
        tester,
        find.descendant(
          of: find.widgetWithText(AppTile, option),
          matching: find.byType(Checkbox),
        ),
      );
    }
    await tap(tester, find.text('>'));
    await tap(tester, find.text('核对答案'));
    await waitFor(tester, () => find.text('这项答对了').evaluate().isNotEmpty);
    await visible(tester, find.text('完成本次练习'));
    final progress = await io(tester, () => repository().load());
    expect(progress.history.single.result, MathTextbookResult.correct);
    expect(progress.history.single.answers, {
      'length': '100厘米',
      'division': '3…2',
      'choice': '["甲","丙"]',
      'comparison': '>',
    });
  });

  testWidgets('纸上题完成只显示待家长核对，孩子记录不能绕过家长保护', (tester) async {
    await tester.runAsync(
      () => install(mathLearningFixture(manual: true), approve: false),
    );
    lockParentForTesting();
    await mount(
      tester,
      AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
    );
    await waitFor(tester, () => input('纸上完成情况').evaluate().isNotEmpty);
    await enter(tester, '纸上完成情况', '已在纸上画出5个圆。');
    await tap(tester, find.text('核对答案'));
    await waitFor(tester, () => find.text('完成本次练习').evaluate().isNotEmpty);
    await tap(tester, find.text('完成本次练习'));
    await waitFor(tester, () => find.text('本次练习已完成').evaluate().isNotEmpty);
    expect(find.text('1 题待家长核对'), findsOneWidget);
    await capture?.call(tester, 'parent-pending');
    expect(find.textContaining('自动核对通过'), findsNothing);
    expect(HiveBoxes.mathSessions.values.single.totalProblems, 0);
    router!.go(AppRoutes.mathTextbookHistoryOf(book.pdfSha256));
    await waitFor(tester, () => find.text('请家长核对开放题').evaluate().isNotEmpty);
    await tap(tester, find.text('请家长核对开放题'));
    await waitFor(tester, () => find.text('请由家长解锁后继续').evaluate().isNotEmpty);
    expect(find.text('作答记录与家长核对'), findsNothing);
    final progress = await io(tester, () => repository().load());
    expect(progress.history.single.result, MathTextbookResult.pendingParent);
  });

  testWidgets('档案切换锁住旧页面，切回仍恢复原档案已保存草稿', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture()));
    await mount(
      tester,
      AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
    );
    await waitFor(tester, () => input('你的答案').evaluate().isNotEmpty);
    await enter(tester, '你的答案', '5');
    await tester.pump(const Duration(milliseconds: 450));
    await waitFor(tester, () {
      final stored = PracticeDraftRepository().get(
        MathTextbookLearningRepository.draftKind,
        scope: jsonEncode([book.pdfSha256, lesson.id, null]),
      );
      return stored != null &&
          MathTextbookPracticeDraft.fromJson(stored).answers.single['answer'] ==
              '5';
    });
    await drainHiveWritesForTesting(tester);
    ProfileScope.switchTo('child-two');
    await waitFor(
      tester,
      () => find.textContaining('孩子档案已切换').evaluate().isNotEmpty,
    );
    expect(tester.widget<TextField>(input('你的答案')).enabled, isFalse);
    final check = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '核对答案'),
    );
    expect(check.onPressed, isNull);
    expect((await io(tester, () => repository().load())).history, isEmpty);
    router!.go(AppRoutes.mathTextbookHistoryOf(book.pdfSha256));
    await waitFor(
      tester,
      () =>
          find.text('还没有本书作答').evaluate().isNotEmpty &&
          find.byType(MathTextbookPracticePage).evaluate().isEmpty,
    );
    ProfileScope.switchTo('default');
    router!.go(AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id));
    await waitFor(tester, () => input('你的答案').evaluate().isNotEmpty);
    expect(tester.widget<TextField>(input('你的答案')).controller!.text, '5');
    expect(tester.widget<TextField>(input('你的答案')).enabled, isTrue);
  });

  testWidgets('同一路由更换巩固计划会载入对应题组而非复用原题页面状态', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture()));
    await mount(
      tester,
      AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
    );
    await waitFor(tester, () => input('你的答案').evaluate().isNotEmpty);
    expect(find.text('1 / 1'), findsOneWidget);
    router!.go(
      AppRoutes.mathTextbookPracticeOf(
        book.pdfSha256,
        lesson.id,
        planId: 'plan',
      ),
    );
    await waitFor(
      tester,
      () => find.text('按本课已审核范围生成的巩固题').evaluate().isNotEmpty,
    );
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('原书第1题'), findsNothing);
  });

  testWidgets('家长编辑保留关联、拒绝移除被引用知识点，覆盖变更后保存待核课时', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture()));
    await mount(
      tester,
      AppRoutes.mathTextbookLessonOf(book.pdfSha256, lesson.id),
      size: const Size(1000, 500),
      scale: 2,
      brightness: Brightness.dark,
    );
    await waitFor(tester, () => find.text('原书范围与待整理内容').evaluate().isNotEmpty);
    await tap(tester, find.text('原书范围与待整理内容'));
    await waitFor(
      tester,
      () => find.text('知识点、教材原题与本课巩固').evaluate().isNotEmpty,
    );
    await tap(tester, find.text('知识点、教材原题与本课巩固'));
    await waitFor(
      tester,
      () => find.byType(MathTextbookLearningEditorPage).evaluate().isNotEmpty,
    );
    await capture?.call(tester, 'parent-editor-landscape');
    await tap(tester, find.byTooltip('移除合并数量'));
    await visible(tester, find.textContaining('请先调整引用这个知识点'));
    await waitFor(
      tester,
      () => find.textContaining('请先调整引用这个知识点').evaluate().isNotEmpty,
    );
    await enter(tester, '所属单元', '重新核对的自有单元');
    await tap(tester, find.text('应用到课时草稿'));
    await waitFor(
      tester,
      () =>
          find.byType(MathTextbookLessonPage).evaluate().isNotEmpty &&
          find.byType(MathTextbookLearningEditorPage).evaluate().isEmpty,
    );
    await tap(tester, find.text('保存草稿'));
    await waitFor(tester, () => find.text('课时草稿已保存').evaluate().isNotEmpty);
    final saved = await io(tester, () => courses.load(book));
    expect(saved!.lessons.single.learning!.unitTitle, '重新核对的自有单元');
    expect(saved.lessons.single.learning!.coverageConfirmed, isFalse);
    expect(saved.lessons.single.learning!.knowledgePoints.single.blockIds, [
      'example',
    ]);
    expect(saved.lessons.single.isApproved(book.pdfSha256), isFalse);
  });
}
