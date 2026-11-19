import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/data/repositories/math_textbook_learning_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/features/textbook/math_textbook_learning_editor_page.dart';
import 'package:poemath/features/textbook/math_textbook_lesson_page.dart';
import 'package:poemath/features/textbook/math_textbook_practice_page.dart';
import 'package:poemath/features/textbook/math_textbook_study_page.dart';
import 'package:poemath/features/textbook/textbook_reader_page.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_knowledge_images.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';
import '../../helpers/parent_access_test_helper.dart';

class _TaskClarityFiles extends TextbookFileService {
  _TaskClarityFiles(Directory directory)
    : super(directoryProvider: () async => directory);
  @override
  Future<String?> installedPath(Textbook book) async => '/self-owned-task.pdf';
}

MathTextbookLesson _mathLearningFixtureWithPageScopedExercises() {
  final lesson = mathLearningFixture();
  final learning = lesson.learning!;
  final firstPageBlock = MathTextbookBlock(
    id: 'exercise-page-1',
    kind: MathTextbookBlockKind.exercise,
    exerciseNumber: '2',
    spans: const [MathTextbookSpan.text('3 + 2 = ?')],
    sources: const [
      MathTextbookRegion(page: 1, left: .1, top: .45, right: .9, bottom: .7),
    ],
  );
  final firstPageExercise = MathTextbookExercise.fromJson({
    ...learning.exercises.single.toJson(),
    'id': 'ex-page-1',
    'title': '原书第2题',
    'number': '2',
    'blockIds': [firstPageBlock.id],
  });
  return MathTextbookLesson.fromJson({
    ...lesson.toJson(),
    'blocks': [
      ...lesson.blocks.map((block) => block.toJson()),
      firstPageBlock.toJson(),
    ],
    'learning': {
      ...learning.toJson(),
      'exercises': [
        ...learning.exercises.map((exercise) => exercise.toJson()),
        firstPageExercise.toJson(),
      ],
    },
  });
}

MathTextbookLesson _mathLearningFixtureWithVariableCardHeights() {
  final source = _mathLearningFixtureWithPageScopedExercises();
  final learning = source.learning!;
  final point = learning.knowledgePoints.single.toJson();
  final plan = learning.practicePlans.single.toJson();
  return MathTextbookLesson.fromJson({
    ...source.toJson(),
    'learning': {
      ...learning.toJson(),
      'knowledgePoints': [
        point,
        {
          ...point,
          'id': 'kp-long',
          'title': '根据数量关系选择计算方法',
          'summary': '观察题目中的数量变化，再选择合适的运算方法并检查结果。' * 30,
        },
        {
          ...point,
          'id': 'kp-short-2',
          'title': '快速检查',
          'summary': '重新计算后核对结果。',
        },
        {
          ...point,
          'id': 'kp-short-3',
          'title': '整理数量',
          'summary': '用算式表达图示数量。',
        },
      ],
      'practicePlans': [
        plan,
        {
          ...plan,
          'id': 'plan-long',
          'knowledgePointId': 'kp-long',
          'title': '根据本节课的知识点逐步加强数量关系练习',
        },
        {
          ...plan,
          'id': 'plan-short-2',
          'knowledgePointId': 'kp-short-2',
          'title': '快速巩固',
        },
        {
          ...plan,
          'id': 'plan-short-3',
          'knowledgePointId': 'kp-short-3',
          'title': '独立练习',
        },
      ],
    },
  });
}

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
    List<MathTextbookRegion>? renderedSources,
    MathTextbookKnowledgeImageLoader? knowledgeImageLoader,
    TextbookViewerBuilder? viewerBuilder,
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
    router = renderedSources == null && viewerBuilder == null
        ? createAppRouter(initialLocation: location)
        : GoRouter(
            initialLocation: location,
            routes: [
              GoRoute(
                path: AppRoutes.mathTextbookBook,
                builder: (_, state) => MathTextbookBookPage(
                  bookId: state.pathParameters['id']!,
                  mode: state.uri.queryParameters['mode'],
                  currentPages: state.uri.queryParameters['pages']
                      ?.split(',')
                      .map(int.parse)
                      .toList(),
                ),
              ),
              GoRoute(
                path: AppRoutes.mathTextbookStudy,
                builder: (_, state) => MathTextbookStudyPage(
                  bookId: state.pathParameters['id']!,
                  lessonId: state.pathParameters['lesson']!,
                  mode: state.uri.queryParameters['mode'],
                  knowledgePointId: state.uri.queryParameters['point'],
                  exampleId: state.uri.queryParameters['example'],
                  viewerBuilder: viewerBuilder,
                ),
              ),
              GoRoute(
                path: AppRoutes.mathTextbookPractice,
                builder: (_, state) => MathTextbookPracticePage(
                  bookId: state.pathParameters['id']!,
                  lessonId: state.pathParameters['lesson']!,
                  planId: state.uri.queryParameters['plan'],
                  exerciseIds: state.uri.queryParameters['exercises']
                      ?.split(',')
                      .toSet(),
                ),
              ),
              GoRoute(
                path: AppRoutes.textbookReadOf(book.pdfSha256),
                builder: (_, state) => Scaffold(
                  appBar: AppBar(title: const Text('完整原书')),
                  body: Text('原书 PDF 第 ${state.extra} 页'),
                ),
              ),
            ],
          );
    await tester.runAsync(
      () => tester.pumpWidget(
        ProviderScope(
          overrides: [
            textbookRepositoryProvider.overrideWithValue(books),
            mathTextbookRepositoryProvider.overrideWithValue(courses),
            textbookCatalogProvider.overrideWith((ref) async => []),
            textbookFileServiceProvider.overrideWithValue(
              _TaskClarityFiles(directory),
            ),
            mathTextbookKnowledgeImageLoaderProvider.overrideWithValue(
              knowledgeImageLoader ?? (path, point, blocks, token) async => [],
            ),
            mathTextbookExampleRendererProvider.overrideWith(
              (ref) => ref.read(mathTextbookRegionRendererProvider),
            ),
            mathTextbookRegionRendererProvider.overrideWithValue((
              path,
              source,
              token,
            ) async {
              token.check();
              renderedSources?.add(source);
              final height =
                  source.left == 0 &&
                      source.top == 0 &&
                      source.right == 1 &&
                      source.bottom == 1
                  ? 340
                  : 120;
              final recorder = ui.PictureRecorder();
              ui.Canvas(recorder).drawRect(
                ui.Rect.fromLTWH(0, 0, 240, height.toDouble()),
                ui.Paint()..color = Colors.white,
              );
              final picture = recorder.endRecording();
              try {
                return picture.toImageSync(240, height);
              } finally {
                picture.dispose();
              }
            }),
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
    await tester.pump(const Duration(milliseconds: 400));
    await waitFor(tester, () => find.byType(Scrollable).evaluate().isNotEmpty);
    if (finder.evaluate().isEmpty) {
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      state.position.jumpTo(state.position.minScrollExtent);
      await tester.pump();
    }
    for (var attempt = 0; attempt < 45; attempt++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (finder.hitTestable().evaluate().isNotEmpty) {
          expect(finder, findsOneWidget);
          expect(tester.takeException(), isNull);
          return;
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await waitFor(
        tester,
        () => find.byType(Scrollable).evaluate().isNotEmpty,
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
    expect(finder.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await visible(tester, finder);
    await tester.runAsync(() => tester.tap(finder));
    await tester.pump();
  }

  Future<void> waitForImages(WidgetTester tester) => waitFor(tester, () {
    final previews = find.byType(MathTextbookSourcePreview);
    return previews.evaluate().isNotEmpty &&
        find
                .descendant(of: previews, matching: find.byType(RawImage))
                .evaluate()
                .length ==
            previews.evaluate().length;
  });

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> enter(WidgetTester tester, String label, String text) async {
    await visible(tester, input(label));
    await tester.enterText(input(label), text);
  }

  for (final manual in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('首道文字原题直接显示原书题面并保留旧稿（纸上：$manual，大字：$large）', (tester) async {
        final source = mathLearningFixture(manual: manual);
        final exercise = source.learning!.exercises.single;
        final value = manual
            ? MathTextbookLesson.fromJson({
                ...source.toJson(),
                'learning': {
                  ...source.learning!.toJson(),
                  'exercises': [
                    {
                      ...exercise.toJson(),
                      'fields': [
                        {
                          ...exercise.fields.single.toJson(),
                          'label': '你的作答或纸上完成情况',
                        },
                      ],
                    },
                  ],
                },
              })
            : source;
        await tester.runAsync(() => install(value, approve: !manual));
        final initialText = manual ? '已经画好两个圆' : '2';
        final previous = await tester.runAsync(() async {
          final repo = repository();
          final draft = (await repo.start(lesson.id)).copyWith(
            elapsedSeconds: 12,
            answers: [
              {'answer': initialText},
            ],
          );
          await repo.saveDraft(draft);
          return draft;
        });
        lockParentForTesting();
        final rendered = <MathTextbookRegion>[];
        await mount(
          tester,
          AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
          size: Size(large ? 320 : 420, 860),
          scale: large ? 2 : 1,
          brightness: large ? Brightness.dark : Brightness.light,
          renderedSources: rendered,
        );
        await waitFor(tester, () => rendered.isNotEmpty);
        await waitForImages(tester);
        expect(previous!.items.single.blocks.single.needsSource, isFalse);
        expect(find.text('1 / 1'), findsNothing);
        expect(find.text('原书第1题'), findsNothing);
        expect(find.text('PDF 第 2 页'), findsNothing);
        expect(find.text('按原书要求完成作答或操作，再在下方记录结果，提交给家长核对。'), findsNothing);
        expect(
          find.text(
            previous.items.single.blocks.single.text,
            findRichText: true,
          ),
          findsOneWidget,
        );
        final content = find.byType(MathTextbookStudyContent);
        expect(
          find.descendant(
            of: content,
            matching: find.byType(MathTextbookSourcePreview),
          ),
          findsOneWidget,
        );
        expect(rendered.first.toJson(), {
          ...previous.items.single.blocks.single.sources.single.toJson(),
          'left': 0.0,
          'top': 0.0,
          'right': 1.0,
          'bottom': 1.0,
        });
        expect(find.text('参考例 2'), findsNothing);
        expect(find.text('查看文字'), findsNothing);
        final action = find.widgetWithText(
          FilledButton,
          manual ? '提交给家长核对' : '核对答案',
        );
        expect(action.hitTestable(), findsOneWidget);
        final beforeScroll = tester.getRect(action);
        expect(beforeScroll.bottom, closeTo(860 - SpacingTokens.md, .01));
        final viewport = tester.getRect(find.byType(Scrollable).first);
        expect(viewport.height, greaterThan(0));
        expect(viewport.bottom, lessThanOrEqualTo(beforeScroll.top));
        final label = manual ? '答案或完成情况' : '你的答案';
        await visible(tester, input(label));
        expect(tester.getRect(action), beforeScroll);
        expect(
          tester.widget<TextField>(input(label)).controller!.text,
          initialText,
        );
        await tester.tap(input(label));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(action).bottom,
          closeTo(beforeScroll.bottom - 300, .01),
        );
        expect(
          tester.getRect(find.byType(Scrollable).first).height,
          greaterThan(0),
        );
        expect(
          tester.widget<TextField>(input(label)).controller!.text,
          initialText,
        );
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final finalText = manual ? '已经在纸上画好5个圆' : '5';
        await enter(tester, label, finalText);
        await tester.runAsync(() => tester.tap(find.byTooltip('打开原书')));
        await waitFor(
          tester,
          () => find.text('原书 PDF 第 2 页').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        router!.pop();
        await tester.pumpAndSettle();
        await visible(tester, input(label));
        expect(
          tester.widget<TextField>(input(label)).controller!.text,
          finalText,
        );
        await tap(tester, find.text(manual ? '提交给家长核对' : '核对答案'));
        final expected = manual
            ? MathTextbookResult.pendingParent
            : MathTextbookResult.correct;
        await waitFor(tester, () {
          final raw = PracticeDraftRepository().get(
            MathTextbookLearningRepository.draftKind,
            scope: previous.scope,
          );
          return raw != null &&
              MathTextbookPracticeDraft.fromJson(raw).results.single ==
                  expected;
        });
        final finish = find.widgetWithText(FilledButton, '完成本次练习');
        await waitFor(tester, () => finish.evaluate().isNotEmpty);
        expect(finish.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(finish).bottom,
          closeTo(beforeScroll.bottom, .01),
        );
        final progress = await io(tester, () => repository().load());
        expect(
          progress.history.single.item.toJson(),
          previous.items.single.toJson(),
        );
        expect(progress.history.single.answers, {'answer': finalText});
        expect(progress.history.single.result, expected);
        final raw = PracticeDraftRepository().get(
          MathTextbookLearningRepository.draftKind,
          scope: previous.scope,
        );
        expect(
          MathTextbookPracticeDraft.fromJson(raw).fingerprint,
          previous.fingerprint,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final large in [false, true]) {
    testWidgets('本课实践显示原书与任务，读原书保留旧输入，提交只待家长核对（大字：$large）', (tester) async {
      await tester.runAsync(
        () => install(
          mathTaskClarityFixture(genericPractice: !large),
          approve: false,
        ),
      );
      final previous = await tester.runAsync(() async {
        final repo = repository();
        final draft = (await repo.start(lesson.id, planId: 'plan')).copyWith(
          elapsedSeconds: 12,
          answers: [
            {'answer': '已经标出顶点'},
          ],
        );
        await repo.saveDraft(draft);
        return draft;
      });
      lockParentForTesting();
      final rendered = <MathTextbookRegion>[];
      await mount(
        tester,
        AppRoutes.mathTextbookPracticeOf(
          book.pdfSha256,
          lesson.id,
          planId: 'plan',
        ),
        size: Size(large ? 320 : 420, 860),
        scale: large ? 2 : 1,
        brightness: large ? Brightness.dark : Brightness.light,
        renderedSources: rendered,
      );
      const answerLabel = '答案或完成情况';
      await waitFor(tester, () => rendered.isNotEmpty);
      final instruction = mathTextbookPaperTaskInstruction(
        lesson.learning!.practicePlans.single.task,
      );
      expect(find.text('本课实践'), findsOneWidget);
      expect(find.text('1 / 1'), findsNothing);
      expect(find.text('实践任务'), findsNothing);
      expect(find.textContaining(RegExp(r'^(书本|PDF) 第 .+ 页$')), findsNothing);
      expect(find.text('按原书要求完成作答或操作，再在下方记录结果，提交给家长核对。'), findsNothing);
      expect(find.text('可在纸上或用实物完成'), findsNothing);
      expect(find.text('本课巩固'), findsNothing);
      expect(find.text(instruction, findRichText: true), findsOneWidget);
      expect(find.text('查看文字'), findsNothing);
      expect(
        rendered.single.toJson(),
        previous!.items.single.blocks.single.sources.single.toJson(),
      );
      await visible(tester, input(answerLabel));
      expect(
        tester.widget<TextField>(input(answerLabel)).controller!.text,
        '已经标出顶点',
      );
      await enter(tester, answerLabel, '已经标出顶点和两条边');
      await tester.pump(const Duration(milliseconds: 450));
      await waitFor(tester, () {
        final stored = PracticeDraftRepository().get(
          MathTextbookLearningRepository.draftKind,
          scope: previous.scope,
        );
        return stored != null &&
            MathTextbookPracticeDraft.fromJson(stored)
                    .answers
                    .single['answer'] ==
                '已经标出顶点和两条边';
      });
      await tester.runAsync(() => tester.tap(find.byTooltip('打开原书')));
      await waitFor(
        tester,
        () => find.text('原书 PDF 第 1 页').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      router!.pop();
      await tester.pumpAndSettle();
      await visible(tester, input(answerLabel));
      expect(
        tester.widget<TextField>(input(answerLabel)).controller!.text,
        '已经标出顶点和两条边',
      );
      final raw = PracticeDraftRepository().get(
        MathTextbookLearningRepository.draftKind,
        scope: previous.scope,
      );
      expect(
        MathTextbookPracticeDraft.fromJson(raw).fingerprint,
        previous.fingerprint,
      );
      await tap(tester, find.text('提交给家长核对'));
      await waitFor(tester, () {
        final raw = PracticeDraftRepository().get(
          MathTextbookLearningRepository.draftKind,
          scope: previous.scope,
        );
        return raw != null &&
            MathTextbookPracticeDraft.fromJson(raw).results.single ==
                MathTextbookResult.pendingParent;
      });
      await visible(tester, find.text('完成本次练习'));
      final progress = await io(tester, () => repository().load());
      expect(progress.history.single.result, MathTextbookResult.pendingParent);
      expect(
        progress.history.single.item.toJson(),
        previous.items.single.toJson(),
      );
      expect(progress.history.single.answers, {'answer': '已经标出顶点和两条边'});
      expect(HiveBoxes.mathSessions.values, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('照例2的原题显示对应原书示范，跳转使用PDF页码并保留作答（大字：$large）', (tester) async {
      await tester.runAsync(
        () => install(mathTaskClarityFixture(), approve: false),
      );
      lockParentForTesting();
      final rendered = <MathTextbookRegion>[];
      await mount(
        tester,
        AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
        size: Size(large ? 320 : 420, 860),
        scale: large ? 2 : 1,
        brightness: large ? Brightness.dark : Brightness.light,
        renderedSources: rendered,
      );
      await waitFor(
        tester,
        () =>
            find.text('参考例 2').evaluate().isNotEmpty &&
            rendered.any((source) => source.page == 1) &&
            rendered.any((source) => source.page == 2),
      );
      await waitForImages(tester);
      expect(find.text('教材原题'), findsOneWidget);
      expect(
        find.text('照例2的方法，画一个角并标出顶点和两条边。', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('书本第 8 页'), findsNothing);
      await visible(tester, find.text('书本第 7 页'));
      expect(find.text('书本第 7 页'), findsOneWidget);
      expect(
        rendered.firstWhere((source) => source.page == 1).toJson(),
        lesson.blocks.first.sources.single.toJson(),
      );
      expect(rendered.firstWhere((source) => source.page == 2).toJson(), {
        ...lesson.blocks.last.sources.single.toJson(),
        'left': 0.0,
        'top': 0.0,
        'right': 1.0,
        'bottom': 1.0,
      });
      expect(find.text('查看文字'), findsNothing);
      await enter(tester, '纸上完成情况', '按示范在纸上画好了');
      await tap(tester, find.text('参考例 2'));
      await waitFor(
        tester,
        () => find.text('原书 PDF 第 1 页').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      router!.pop();
      await tester.pumpAndSettle();
      await visible(tester, input('纸上完成情况'));
      expect(
        tester.widget<TextField>(input('纸上完成情况')).controller!.text,
        '按示范在纸上画好了',
      );
      await tester.runAsync(() => tester.tap(find.byTooltip('打开原书')));
      await waitFor(
        tester,
        () => find.text('原书 PDF 第 2 页').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      router!.pop();
      await tester.pumpAndSettle();
      await visible(tester, input('纸上完成情况'));
      expect(
        tester.widget<TextField>(input('纸上完成情况')).controller!.text,
        '按示范在纸上画好了',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('仅有做一做标题的原题直接显示完整原页', (tester) async {
    final source = mathTaskClarityFixture();
    final exercise = source.learning!.exercises.single;
    final headingOnly = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'blocks': [
        source.blocks.first.toJson(),
        {
          ...source.blocks.last.toJson(),
          'exerciseNumber': null,
          'sourceLayout': true,
          'spans': [const MathTextbookSpan.text('做一做').toJson()],
        },
      ],
      'learning': {
        ...source.learning!.toJson(),
        'exercises': [
          {...exercise.toJson(), 'title': '做一做', 'number': ''},
        ],
      },
    });
    await tester.runAsync(() => install(headingOnly, approve: false));
    final rendered = <MathTextbookRegion>[];
    await mount(
      tester,
      AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
      renderedSources: rendered,
    );
    await waitFor(tester, () => rendered.isNotEmpty);
    expect(rendered.single.page, 2);
    expect(rendered.single.printedPage, '8');
    expect(rendered.single.top, 0);
    expect(rendered.single.bottom, 1);
    expect(find.text('做一做'), findsNothing);
    expect(find.text('书本第 8 页'), findsNothing);
    expect(find.text('请完成下方完整原页中“做一做”的题目，再记录结果，提交给家长核对。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未审课可阅读本课内容，未核对的自动答案仍不判分', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture(), approve: false));
    lockParentForTesting();
    await mount(
      tester,
      AppRoutes.mathTextbookStudyOf(book.pdfSha256, lesson.id),
    );
    await waitFor(tester, () => find.text('看一看').evaluate().isNotEmpty);
    expect(find.text('本课待家长核对'), findsNothing);
    await tap(tester, find.text('看一看'));
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

  testWidgets('显式选择原题的草稿不覆盖整课草稿', (tester) async {
    await tester.runAsync(
      () => install(_mathLearningFixtureWithPageScopedExercises()),
    );
    final drafts = await io(tester, () async {
      final repo = repository();
      final whole = await repo.start(lesson.id);
      final firstPage = await repo.start(lesson.id, exerciseIds: {'ex-page-1'});
      final secondPage = await repo.start(lesson.id, exerciseIds: {'ex'});
      return (
        whole: whole,
        firstPage: firstPage,
        secondPage: secondPage,
        wholeReload: await repo.loadDraft(lesson.id),
        firstPageReload: await repo.loadDraft(
          lesson.id,
          exerciseIds: {'ex-page-1'},
        ),
        secondPageReload: await repo.loadDraft(lesson.id, exerciseIds: {'ex'}),
      );
    });

    expect(drafts.whole.exerciseIds, isNull);
    expect(drafts.firstPage.exerciseIds, ['ex-page-1']);
    expect(drafts.firstPage.items.map((item) => item.exercise.id), [
      'ex-page-1',
    ]);
    expect(drafts.secondPage.exerciseIds, ['ex']);
    expect(drafts.secondPage.items.map((item) => item.exercise.id), ['ex']);
    expect(drafts.whole.scope, isNot(drafts.firstPage.scope));
    expect(drafts.whole.scope, isNot(drafts.secondPage.scope));
    expect(drafts.firstPage.scope, isNot(drafts.secondPage.scope));
    expect(drafts.wholeReload?.sessionId, drafts.whole.sessionId);
    expect(drafts.firstPageReload?.sessionId, drafts.firstPage.sessionId);
    expect(drafts.secondPageReload?.sessionId, drafts.secondPage.sessionId);
  });

  testWidgets('练习深链恢复限定原题列表', (tester) async {
    await tester.runAsync(
      () => install(_mathLearningFixtureWithPageScopedExercises()),
    );
    await mount(
      tester,
      AppRoutes.mathTextbookPracticeOf(
        book.pdfSha256,
        lesson.id,
        exerciseIds: {'ex-page-1'},
      ),
    );
    await waitFor(tester, () => find.byType(TextField).evaluate().isNotEmpty);

    expect(
      tester
          .widget<MathTextbookPracticePage>(
            find.byType(MathTextbookPracticePage),
          )
          .exerciseIds,
      {'ex-page-1'},
    );
    final raw = PracticeDraftRepository().get(
      MathTextbookLearningRepository.draftKind,
      scope: jsonEncode([
        book.pdfSha256,
        lesson.id,
        null,
        ['ex-page-1'],
      ]),
    );
    expect(
      MathTextbookPracticeDraft.fromJson(raw).items
          .map((item) => item.exercise.id),
      ['ex-page-1'],
    );
  });

  testWidgets('学一学和做一做按卡片自然高度瀑布流排布', (tester) async {
    await tester.runAsync(
      () => install(_mathLearningFixtureWithVariableCardHeights()),
    );
    await mount(
      tester,
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookLearnMode,
        pages: [lesson.startPage],
      ),
      size: const Size(1200, 1100),
    );

    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '整理数量').evaluate().isNotEmpty,
    );
    void expectWaterfall(String key, List<String> titles) {
      final masonry = find.byKey(ValueKey(key));
      expect(tester.widget<MasonryLayout>(masonry).columnCount, 3);
      final cards = [
        for (final title in titles)
          tester.getRect(find.widgetWithText(AppTile, title)),
      ];
      final viewport = tester.getRect(find.byType(CustomScrollView));
      for (final card in cards) {
        expect(
          card.left,
          greaterThanOrEqualTo(viewport.left + SpacingTokens.md),
        );
        expect(
          card.right,
          lessThanOrEqualTo(viewport.right - SpacingTokens.md),
        );
      }
      expect(
        cards.first.top,
        greaterThanOrEqualTo(viewport.top + SpacingTokens.md),
      );
      expect(cards[0].top, closeTo(cards[1].top, .1));
      expect(cards[1].top, closeTo(cards[2].top, .1));
      expect(cards[0].left, lessThan(cards[1].left));
      expect(cards[1].left, lessThan(cards[2].left));
      expect(cards[0].height, lessThan(cards[1].height));
      final shortestBottom = [
        cards[0].bottom,
        cards[1].bottom,
        cards[2].bottom,
      ].reduce((first, second) => first < second ? first : second);
      final tallestBottom = [
        cards[0].bottom,
        cards[1].bottom,
        cards[2].bottom,
      ].reduce((first, second) => first > second ? first : second);
      expect(cards[3].top, closeTo(shortestBottom + SpacingTokens.sm, .1));
      expect(cards[3].top, lessThan(tallestBottom));
    }

    expectWaterfall('math-textbook-knowledge-masonry', [
      '合并数量',
      '根据数量关系选择计算方法',
      '快速检查',
      '整理数量',
    ]);

    router!.go(
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookPracticeMode,
        pages: [lesson.startPage],
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '独立练习').evaluate().isNotEmpty,
    );
    expectWaterfall('math-textbook-practice-masonry', [
      '教材原题',
      '本课巩固',
      '根据本节课的知识点逐步加强数量关系练习',
      '快速巩固',
    ]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final card = tester.getRect(find.widgetWithText(AppTile, '教材原题'));
    expect(card.left, viewport.left + SpacingTokens.md);
    expect(card.right, viewport.right - SpacingTokens.md);
    expect(
      tester
          .widget<MasonryLayout>(
            find.byKey(const ValueKey('math-textbook-practice-masonry')),
          )
          .columnCount,
      1,
    );
  });

  testWidgets('学一学包含知识配图和完整例题，做一做只保留原题与练习', (tester) async {
    final fixture = mathMisclassifiedPracticeFixture(illustratedHeading: true);
    final illustrated = fixture.edit(
      blocks: [
        for (final block in fixture.blocks)
          if (block.id == 'example')
            MathTextbookBlock.fromJson({
              ...block.toJson(),
              'sourceLayout': true,
            })
          else
            block,
      ],
    );
    final renderedSources = <MathTextbookRegion>[];
    const teachingImage = MathTextbookRegion(
      page: 1,
      left: .2,
      top: .22,
      right: .8,
      bottom: .35,
    );
    var knowledgeLoads = 0;
    await tester.runAsync(() => install(illustrated, approve: false));
    await mount(
      tester,
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookLearnMode,
        pages: [2],
      ),
      renderedSources: renderedSources,
      knowledgeImageLoader: (path, point, blocks, token) async {
        knowledgeLoads++;
        expect(point.title, '自有长度课');
        expect(blocks.map((block) => block.id), ['example']);
        return [teachingImage];
      },
    );
    await waitFor(tester, () => find.text('自有长度课').evaluate().isNotEmpty);
    expect(find.text('认识角'), findsOneWidget);
    expect(find.widgetWithText(AppTile, '自有长度课 · 例 1'), findsOneWidget);
    expect(find.widgetWithText(AppTile, '认识角 · 例 2'), findsOneWidget);
    expect(find.textContaining('量一量图中的纸条'), findsNothing);
    expect(find.textContaining('再比较两条线段'), findsNothing);
    await tap(tester, find.widgetWithText(AppTile, '自有长度课'));
    await waitFor(
      tester,
      () => find.byType(MathTextbookKnowledgeNotesPage).evaluate().isNotEmpty,
    );
    expect(find.text('用尺子连接两个点，可以得到一条线段。'), findsOneWidget);
    await waitFor(tester, () => renderedSources.isNotEmpty);
    await waitForImages(tester);
    expect(find.byType(MathTextbookSourcePreview), findsOneWidget);
    expect(renderedSources.single, teachingImage);
    expect(
      find.descendant(
        of: find.byType(MathTextbookKnowledgeNotesPage),
        matching: find.byType(ColoredCard),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<MathTextbookSourcePreview>(
            find.byType(MathTextbookSourcePreview),
          )
          .workedExample,
      isFalse,
    );
    router!.pop();
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '自有长度课').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(AppTile, '自有长度课'));
    await waitForImages(tester);
    expect(knowledgeLoads, 1, reason: '再次进入直接复用已定位的知识配图');
    expect(renderedSources, [teachingImage], reason: '再次进入直接读取 PNG，不重渲染 PDF');
    renderedSources.clear();

    router!.pop();
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '自有长度课 · 例 1').evaluate().isNotEmpty,
    );
    await tap(tester, find.widgetWithText(AppTile, '自有长度课 · 例 1'));
    await waitFor(
      tester,
      () => find.byType(MathTextbookSourceContentPage).evaluate().isNotEmpty,
    );
    final examplePage = tester.widget<MathTextbookSourceContentPage>(
      find.byType(MathTextbookSourceContentPage),
    );
    expect(examplePage.workedExample, isTrue);
    expect(examplePage.blocks.map((b) => b.id), ['example']);
    await waitFor(tester, () => renderedSources.isNotEmpty);
    expect(
      tester
          .widget<MathTextbookSourcePreview>(
            find.byType(MathTextbookSourcePreview),
          )
          .workedExample,
      isTrue,
    );
    expect(
      renderedSources.single.toJson(),
      illustrated.blocks.first.sources.single.toJson(),
    );
    expect(find.textContaining('量一量图中的纸条'), findsNothing);
    router!.go(
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookPracticeMode,
        pages: [1],
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('例 1'), findsNothing);
    expect(find.textContaining('例 2'), findsNothing);
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    expect(find.textContaining('量一量图中的纸条'), findsOneWidget);
    final draft = MathTextbookPracticeDraft.fromJson(
      PracticeDraftRepository().get(
        MathTextbookLearningRepository.draftKind,
        scope: jsonEncode([book.pdfSha256, lesson.id, null]),
      ),
    );
    expect(draft.items.map((item) => item.blocks.map((b) => b.id).toList()), [
      ['practice-heading', 'practice-body'],
      ['numbered'],
      ['continued-practice'],
    ]);
    expect(find.byType(MathTextbookSourcePreview), findsWidgets);
  });

  testWidgets('只有完整例题时仍可从学一学打开，教材原题跳过章节导入图', (tester) async {
    final fixture = mathChapterIntroductionFixture(legacy: false);
    expect(mathTextbookStudyNotes(fixture), isEmpty);
    final title = fixture.learning!.knowledgePoints.single.title;
    await tester.runAsync(() => install(fixture, approve: false));
    await mount(
      tester,
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookLearnMode,
        pages: [1],
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, title).evaluate().isNotEmpty,
    );
    expect(find.textContaining('尚未整理'), findsNothing);
    await tap(tester, find.widgetWithText(AppTile, title));
    await waitFor(
      tester,
      () => find.byType(MathTextbookSourceContentPage).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<MathTextbookSourceContentPage>(
            find.byType(MathTextbookSourceContentPage),
          )
          .workedExample,
      isTrue,
    );
    router!.go(
      AppRoutes.mathTextbookStudyOf(
        book.pdfSha256,
        fixture.id,
        mode: AppRoutes.mathTextbookLearnMode,
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, title).evaluate().isNotEmpty,
    );
    router!.go(
      AppRoutes.mathTextbookStudyOf(
        book.pdfSha256,
        fixture.id,
        mode: AppRoutes.mathTextbookPracticeMode,
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppTile, title), findsNothing);
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    expect(find.textContaining('在纸上画出5个圆'), findsOneWidget);
    expect(find.textContaining('（3）班'), findsNothing);
  });

  testWidgets('切换知识点取消旧配图，配图失败仍保留讲解并可重试', (tester) async {
    final source = mathTaskClarityFixture();
    final first = source.learning!.knowledgePoints.single;
    final second = MathTextbookKnowledgePoint(
      id: 'another-point',
      title: '角的边',
      summary: '两条边从同一个顶点出发。',
      blockIds: first.blockIds,
    );
    final fixture = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {
        ...source.learning!.toJson(),
        'knowledgePoints': [first.toJson(), second.toJson()],
      },
    });
    await tester.runAsync(() => install(fixture, approve: false));
    final oldImage = Completer<List<MathTextbookRegion>>();
    bool Function()? oldCancelled;
    var attempts = 0;
    final rendered = <MathTextbookRegion>[];
    const newRegion = MathTextbookRegion(
      page: 1,
      left: .3,
      top: .15,
      right: .8,
      bottom: .25,
    );
    String location(String id) => AppRoutes.mathTextbookStudyOf(
      book.pdfSha256,
      lesson.id,
      mode: AppRoutes.mathTextbookLearnMode,
      knowledgePointId: id,
    );
    await mount(
      tester,
      location(first.id),
      size: const Size(320, 860),
      scale: 2,
      renderedSources: rendered,
      knowledgeImageLoader: (path, point, blocks, token) async {
        if (point.id == first.id) {
          oldCancelled = () => token.cancelled;
          return oldImage.future;
        }
        if (++attempts == 1) throw const FormatException('配图读取失败，请重试');
        return [newRegion];
      },
    );
    await waitFor(tester, () => oldCancelled != null);
    router!.go(location(second.id));
    await waitFor(tester, () => find.text('重新加载配图').evaluate().isNotEmpty);
    expect(oldCancelled!(), isTrue);
    expect(find.text(second.summary), findsOneWidget);
    oldImage.complete([fixture.blocks.first.sources.single]);
    await tester.pump();
    expect(rendered, isEmpty);
    await tap(tester, find.text('重新加载配图'));
    await waitFor(tester, () => rendered.isNotEmpty);
    expect(rendered, [newRegion]);
    expect(find.text('配图读取失败，请重试'), findsNothing);
    expect(find.text(second.summary), findsOneWidget);
  });

  testWidgets('同一课时任意页都能打开完整知识点、原题与巩固，并恢复同一草稿', (tester) async {
    await tester.runAsync(
      () => install(_mathLearningFixtureWithPageScopedExercises()),
    );
    await mount(
      tester,
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookReadMode,
      ),
      viewerBuilder: (_, options) => Text('原书第 ${options.initialPage} 页'),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, lesson.title).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<MathTextbookBookPage>(find.byType(MathTextbookBookPage))
          .mode,
      AppRoutes.mathTextbookReadMode,
    );
    await tap(tester, find.widgetWithText(AppTile, lesson.title));
    await waitFor(
      tester,
      () => find.byType(TextbookReaderPage).evaluate().isNotEmpty,
    );
    final reader = tester.widget<TextbookReaderPage>(
      find.byType(TextbookReaderPage),
    );
    expect(reader.initialPage, lesson.startPage);
    expect(reader.title, lesson.title);
    expect(reader.bottomAction, isNotNull);
    expect(find.text('原书第 ${lesson.startPage} 页'), findsOneWidget);
    expect(find.text('看完本课，标记已读'), findsOneWidget);

    router!.go(
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookLearnMode,
        pages: [lesson.startPage],
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '合并数量').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<MathTextbookBookPage>(find.byType(MathTextbookBookPage))
          .mode,
      AppRoutes.mathTextbookLearnMode,
    );
    expect(
      tester
          .widget<MathTextbookBookPage>(find.byType(MathTextbookBookPage))
          .currentPages,
      [lesson.startPage],
    );
    expect(find.text('学一学'), findsOneWidget);
    await tap(tester, find.widgetWithText(AppTile, '合并数量'));
    await waitFor(
      tester,
      () => find.byType(MathTextbookKnowledgeNotesPage).evaluate().isNotEmpty,
    );
    final knowledgePage = tester.widget<MathTextbookKnowledgeNotesPage>(
      find.byType(MathTextbookKnowledgeNotesPage),
    );
    expect(knowledgePage.point.title, '合并数量');
    expect(find.text('用加法求合并后的数量。'), findsOneWidget);
    expect(find.byType(MathTextbookSourcePreview), findsNothing);

    router!.go(
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookLearnMode,
        pages: [lesson.endPage],
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '合并数量').evaluate().isNotEmpty,
    );
    expect(find.text('当前页尚未整理知识点。'), findsNothing);
    await tap(tester, find.widgetWithText(AppTile, '合并数量'));
    await waitFor(
      tester,
      () => find.byType(MathTextbookKnowledgeNotesPage).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<MathTextbookKnowledgeNotesPage>(
            find.byType(MathTextbookKnowledgeNotesPage),
          )
          .point
          .id,
      knowledgePage.point.id,
    );

    router!.go(
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookPracticeMode,
        pages: [lesson.startPage],
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<MathTextbookBookPage>(find.byType(MathTextbookBookPage))
          .mode,
      AppRoutes.mathTextbookPracticeMode,
    );
    expect(find.text('做一做'), findsOneWidget);
    expect(find.widgetWithText(AppTile, lesson.title), findsNothing);
    expect(find.widgetWithText(AppTile, '本课巩固'), findsOneWidget);
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    expect(find.byType(MathTextbookPracticePage), findsOneWidget);
    expect(
      tester
          .widget<MathTextbookPracticePage>(
            find.byType(MathTextbookPracticePage),
          )
          .exerciseIds,
      isNull,
    );
    MathTextbookPracticeDraft savedLessonDraft() =>
        MathTextbookPracticeDraft.fromJson(
          PracticeDraftRepository().get(
            MathTextbookLearningRepository.draftKind,
            scope: jsonEncode([book.pdfSha256, lesson.id, null]),
          ),
        );
    final firstPageDraft = savedLessonDraft();
    expect(firstPageDraft.items.map((item) => item.exercise.id), [
      'ex',
      'ex-page-1',
    ]);

    router!.go(
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookPracticeMode,
        pages: [lesson.endPage],
      ),
    );
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    expect(find.widgetWithText(AppTile, '本课巩固'), findsOneWidget);
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    expect(
      tester
          .widget<MathTextbookPracticePage>(
            find.byType(MathTextbookPracticePage),
          )
          .exerciseIds,
      isNull,
    );
    final lastPageDraft = savedLessonDraft();
    expect(lastPageDraft.sessionId, firstPageDraft.sessionId);
    expect(lastPageDraft.items.map((item) => item.exercise.id), [
      'ex',
      'ex-page-1',
    ]);
  });

  testWidgets('当前页没有对应课时内容时不展示全书知识点或练习', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture()));
    await mount(
      tester,
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookLearnMode,
        pages: [lesson.endPage + 1],
      ),
    );
    await waitFor(tester, () => find.text('当前页尚未关联课时。').evaluate().isNotEmpty);
    expect(find.widgetWithText(AppTile, '合并数量'), findsNothing);

    router!.go(
      AppRoutes.mathTextbookBookOf(
        book.pdfSha256,
        mode: AppRoutes.mathTextbookPracticeMode,
        pages: [lesson.endPage + 1],
      ),
    );
    await waitFor(tester, () => find.text('当前页尚未关联课时。').evaluate().isNotEmpty);
    expect(find.widgetWithText(AppTile, '教材原题'), findsNothing);
  });

  testWidgets('课时详情用导航栏显示当前课名，不重复显示名称和顶部进度统计', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture()));
    await mount(tester, AppRoutes.mathTextbookBookOf(book.pdfSha256));
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, lesson.title).evaluate().isNotEmpty,
    );
    await tap(tester, find.widgetWithText(AppTile, lesson.title));
    await waitFor(tester, () => find.text('看一看').evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar).last,
        matching: find.text(lesson.title),
      ),
      findsOneWidget,
    );
    expect(find.text(lesson.title), findsOneWidget);
    expect(find.text('本课学习'), findsNothing);
    expect(find.text('看一看'), findsOneWidget);
    expect(find.text('学一学'), findsOneWidget);
    expect(find.text('做一做'), findsOneWidget);
    expect(find.textContaining('原题 0/'), findsNothing);
    expect(find.textContaining('巩固 0/'), findsNothing);

    await tap(tester, find.text('做一做'));
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    expect(find.widgetWithText(AppTile, '本课巩固'), findsOneWidget);
  });

  testWidgets('长摘要以简短入口呈现，双倍字号打开完整知识要点，不展示例题截图', (tester) async {
    final source = mathLearningFixture();
    final knowledge = source.learning!.knowledgePoints.single;
    final long = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {
        ...source.learning!.toJson(),
        'knowledgePoints': [
          {...knowledge.toJson(), 'summary': '用加法求合并后的数量。\n' * 80},
        ],
      },
    });
    await tester.runAsync(() => install(long, approve: false));
    await mount(
      tester,
      AppRoutes.mathTextbookStudyOf(book.pdfSha256, lesson.id),
      size: const Size(320, 860),
      scale: 2,
      brightness: Brightness.dark,
    );
    await waitFor(tester, () => find.text('学一学').evaluate().isNotEmpty);
    await tap(tester, find.text('学一学'));
    await visible(tester, find.text(knowledge.title));
    final entry = find.ancestor(
      of: find.text(knowledge.title),
      matching: find.byType(AppTile),
    );
    expect(tester.getSize(entry).height, lessThan(860 * .65));
    await capture?.call(tester, 'compact-knowledge-index');
    await tap(tester, find.text(knowledge.title));
    await waitFor(
      tester,
      () => find.byType(MathTextbookKnowledgeNotesPage).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<MathTextbookKnowledgeNotesPage>(
            find.byType(MathTextbookKnowledgeNotesPage),
          )
          .point
          .summary,
      '用加法求合并后的数量。\n' * 80,
    );
    expect(find.text('把2个圆和3个圆合在一起，共有5个圆。', findRichText: true), findsNothing);
    final contentPage = find.byType(MathTextbookKnowledgeNotesPage);
    expect(
      find.descendant(of: contentPage, matching: find.byType(ColoredCard)),
      findsNothing,
    );
    final appBar = find.descendant(
      of: contentPage,
      matching: find.byType(AppBar),
    );
    expect(
      find.descendant(of: appBar, matching: find.text(knowledge.title)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byTooltip('打开原书')),
      findsNothing,
    );
    expect(find.byType(MathTextbookSourcePreview), findsNothing);
    expect(
      find.descendant(of: contentPage, matching: find.text('查看文字')),
      findsNothing,
    );
    final saved = await io(tester, () => courses.load(book));
    expect(
      saved!.lessons.single.learning!.knowledgePoints.single.summary,
      '用加法求合并后的数量。\n' * 80,
    );
    expect(tester.takeException(), isNull);
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
      await waitFor(tester, () => find.text('看一看').evaluate().isNotEmpty);
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
        expect(afterRead.pixels, closeTo(offsetBeforeRead, .1));
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
        () => find.widgetWithText(AppTile, lesson.title).evaluate().isNotEmpty,
      );
      await tap(tester, find.widgetWithText(AppTile, lesson.title));
      await waitFor(tester, () => find.text('看一看').evaluate().isNotEmpty);
      await tap(tester, find.text('做一做'));
      await waitFor(
        tester,
        () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
      );
      await tap(tester, find.widgetWithText(AppTile, '教材原题'));
      await waitFor(
        tester,
        () => find.byType(MathTextbookStudyContent).evaluate().isNotEmpty,
      );
      expect(find.text('1 / 1'), findsNothing);
      await visible(tester, input('纸上完成情况'));
      expect(input('你的答案'), findsNothing);
      expect(find.text('本课待家长核对'), findsNothing);
    });
  }

  testWidgets('整书量级课时列表加载与撤审刷新使用对应课程的汇总', (tester) async {
    await tester.runAsync(() => install(denseMathLearningFixture()));
    await mount(tester, AppRoutes.mathTextbookBookOf(book.pdfSha256));
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, lesson.title).evaluate().isNotEmpty,
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
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '更新后的大课时').evaluate().isNotEmpty,
    );
    expect(find.text('更新后的大课时'), findsOneWidget);
    expect(find.text('未读'), findsOneWidget);
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
    await tap(tester, find.text('做一做'));
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await waitFor(
      tester,
      () =>
          find.byType(MathTextbookPracticePage).evaluate().isNotEmpty &&
          input('你的答案').evaluate().isNotEmpty,
    );
    await waitForImages(tester);
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
          find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await waitFor(
      tester,
      () => find.textContaining('已通过 1 组').evaluate().isNotEmpty,
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
    await waitFor(tester, () => find.text('做一做').evaluate().isNotEmpty);
    await tap(tester, find.text('做一做'));
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await visible(tester, input('长度'));
    await waitForImages(tester);
    await enter(tester, '长度', '100厘米');
    await enter(tester, '商', '3');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tap(tester, find.text('核对答案'));
    await waitFor(
      tester,
      () => find.textContaining('请完成本题全部作答项').evaluate().isNotEmpty,
    );
    final validation = find.textContaining('请完成本题全部作答项');
    expect(validation.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(validation).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.widgetWithText(FilledButton, '核对答案')).top,
      ),
    );
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(HiveBoxes.mathSessions.values, isEmpty);
    await tester.runAsync(() => tester.tap(find.byTooltip('保存并返回')));
    await waitFor(
      tester,
      () => find.widgetWithText(AppTile, '教材原题').evaluate().isNotEmpty,
    );
    await tap(tester, find.widgetWithText(AppTile, '教材原题'));
    await visible(tester, input('长度'));
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
    await visible(tester, input('纸上完成情况'));
    await enter(tester, '纸上完成情况', '已在纸上画出5个圆。');
    await tap(tester, find.text('提交给家长核对'));
    await visible(tester, find.text('完成本次练习'));
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
    await visible(tester, input('你的答案'));
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
    await visible(tester, input('你的答案'));
    expect(tester.widget<TextField>(input('你的答案')).enabled, isFalse);
    await visible(tester, find.widgetWithText(FilledButton, '核对答案'));
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
    await visible(tester, input('你的答案'));
    expect(tester.widget<TextField>(input('你的答案')).controller!.text, '5');
    expect(tester.widget<TextField>(input('你的答案')).enabled, isTrue);
  });

  testWidgets('同一路由更换巩固计划会载入对应题组而非复用原题页面状态', (tester) async {
    await tester.runAsync(() => install(mathLearningFixture()));
    await mount(
      tester,
      AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
    );
    await waitFor(
      tester,
      () => find.byType(MathTextbookStudyContent).evaluate().isNotEmpty,
    );
    expect(find.text('1 / 1'), findsNothing);
    await visible(tester, input('你的答案'));
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
    expect(find.byType(MathTextbookSourcePreview), findsNothing);
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
