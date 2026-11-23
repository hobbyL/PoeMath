import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/math_textbook_generation_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/domain/math_textbook_course_plan.dart';
import 'package:poemath/features/textbook/math_textbook_block_editor_page.dart';
import 'package:poemath/features/textbook/math_textbook_lesson_page.dart';
import 'package:poemath/features/textbook/math_textbook_learning_editor_page.dart';
import 'package:poemath/features/textbook/math_textbook_review_page.dart';
import 'package:poemath/features/textbook/math_textbook_study_page.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_review_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';
import '../../helpers/math_textbook_image_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

class _Courses extends MathTextbookCourseRepository {
  MathTextbookCourse? current;
  bool failSave = false;
  Completer<void>? saveGate;
  int saves = 0;
  @override
  Future<MathTextbookCourse?> load(Textbook book) async => current;
  @override
  Future<MathTextbookCourse> acceptPending(
    Textbook book,
    String lessonId, {
    required int expectedRevision,
    required int generation,
    required void Function() authorize,
  }) async {
    authorize();
    if (expectedRevision != current?.revision) {
      throw const FormatException('课时已更新，请重新打开');
    }
    final pending = current!.pendingLessons.firstWhere(
      (lesson) => lesson.id == lessonId,
    );
    current = current!.replace(lessons: [pending], pendingLessons: []);
    return current!;
  }

  @override
  Future<MathTextbookCourse> saveLesson(
    Textbook book,
    MathTextbookLesson lesson, {
    required int expectedRevision,
    required int generation,
    required void Function() authorize,
  }) async {
    authorize();
    saves++;
    await saveGate?.future;
    authorize();
    if (failSave) throw const FileSystemException('disk unavailable');
    if (expectedRevision != current?.revision) {
      throw const FormatException('课时已更新，请重新打开');
    }
    current = current!.replace(lessons: [lesson]);
    return current!;
  }
}

class _Files extends TextbookFileService {
  _Files([Directory? root])
    : super(directoryProvider: root == null ? null : () async => root);
  @override
  Future<String?> installedPath(Textbook book) async => '/self-owned.pdf';
}

class _Generator extends MathTextbookGenerationService {
  _Generator(this.courses) : super(courses, _Files());
  final _Courses courses;
  int calls = 0;
  int bookCalls = 0;
  Completer<void>? bookGate;

  @override
  Future<MathTextbookCourse> generateBook({
    required Textbook book,
    required TextbookDraftToken token,
    required void Function() authorize,
    required void Function(int, int) onProgress,
    void Function(String)? onStatus,
    void Function(int, int)? onLessonProgress,
    void Function()? onSaved,
    bool refresh = false,
    MathTextbookPageLoader? pageLoader,
    TextbookTocResult? toc,
  }) async {
    token.check();
    authorize();
    bookCalls++;
    var course = courses.current ?? MathTextbookCourse.forBook(book);
    if (course.outline == null || refresh) {
      course = course.replace(
        outline: MathTextbookCourseOutline(
          source: 'bookmarks',
          organizationVersion: mathTextbookOrganizationVersion,
          completedLessonIds: const [],
          ranges: const [
            MathTextbookCourseRange(
              title: '自有第一课',
              unitTitle: '第一单元',
              startPage: 1,
              endPage: 2,
            ),
            MathTextbookCourseRange(
              title: '自有第二课',
              unitTitle: '第二单元',
              startPage: 3,
              endPage: 3,
            ),
          ],
        ),
      );
      courses.current = course;
      onSaved?.call();
    }
    final completed = course.outline!.completedLessonIds!.toSet();
    onLessonProgress?.call(completed.length, 2);
    for (final range in course.outline!.ranges) {
      if (completed.contains(range.lessonId)) continue;
      token.check();
      authorize();
      completed.add(range.lessonId);
      course = course.replace(
        lessons: [
          ...course.lessons,
          mathLessonFixture(
            title: range.title,
            start: range.startPage,
            end: range.endPage,
          ),
        ],
        outline: course.outline!.withCompleted(completed),
      );
      courses.current = course;
      onLessonProgress?.call(completed.length, 2);
      onSaved?.call();
      final gate = bookGate;
      bookGate = null;
      if (gate != null) {
        await gate.future;
        token.check();
      }
    }
    return course;
  }

  @override
  Future<MathTextbookCourse> generate({
    required Textbook book,
    required String title,
    required int startPage,
    required int endPage,
    required TextbookDraftToken token,
    required void Function() authorize,
    required void Function(int, int) onProgress,
    MathTextbookPageLoader? pageLoader,
    String unitTitle = '',
    bool needsAlignment = false,
    MathTextbookCourseRange? legacyRange,
  }) async {
    token.check();
    authorize();
    calls++;
    onProgress(endPage - startPage + 1, endPage - startPage + 1);
    final lesson = mathLessonFixture(
      title: title,
      start: startPage,
      end: endPage,
    );
    courses.current = MathTextbookCourse.forBook(book)
        .replace(lessons: [lesson]);
    return courses.current!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final book = mathTextbookFixture();
  late _Courses courses;
  late _Generator generator;
  late Directory imageCache;
  setUp(() async {
    imageCache = await Directory.systemTemp.createTemp('math-review-images-');
    await setUpHiveForTesting();
    await unlockParentForTesting();
    await TextbookRepository().addIfAbsent(book);
    courses = _Courses()
      ..current = MathTextbookCourse.forBook(book)
          .replace(lessons: [mathLessonFixture()]);
    generator = _Generator(courses);
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
    await imageCache.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(420, 860),
    double scale = 1,
    bool knownCatalog = false,
    bool courseGenerationSupported = true,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mathTextbookRepositoryProvider.overrideWithValue(courses),
          mathTextbookGenerationServiceProvider.overrideWithValue(generator),
          textbookFileServiceProvider.overrideWithValue(_Files(imageCache)),
          textbookCatalogProvider.overrideWith(
            (ref) async => knownCatalog
                ? [
                    TextbookCatalogEntry(
                      book: book,
                      downloadUrl: Uri.https('example.com', '/self-owned.pdf'),
                      sourceRepository: 'self-owned/fixtures',
                      sourceCommit: 'fixture-commit',
                      sourcePath: 'self-owned.pdf',
                      editionLabel: '合成样本',
                      evidencePdfPages: const [1],
                      supportsMathCourseGeneration: courseGenerationSupported,
                    ),
                  ]
                : [],
          ),
          mathTextbookRegionRendererProvider.overrideWithValue((
            path,
            source,
            token,
          ) async {
            final recorder = ui.PictureRecorder();
            ui.Canvas(recorder).drawRect(
              const ui.Rect.fromLTWH(0, 0, 120, 80),
              ui.Paint()..color = const ui.Color(0xffffffff),
            );
            final picture = recorder.endRecording();
            try {
              return await picture.toImage(120, 80);
            } finally {
              picture.dispose();
            }
          }),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ParentAccessBoundary(child: child),
        ),
      ),
    );
    if (settle) {
      await settleMathTextbookImages(tester);
    } else {
      await tester.pump();
    }
  }

  Finder input(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> visible(
    WidgetTester tester,
    Finder finder, {
    double delta = 300,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await settleMathTextbookImages(tester);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openSource(WidgetTester tester) async {
    await visible(tester, find.text('原书范围与待整理内容'));
    await tester.tap(find.text('原书范围与待整理内容'));
    await tester.pumpAndSettle();
  }

  testWidgets('题组和作答页直接显示完整原书内容，跨页来源按阅读顺序排列', (tester) async {
    final original = mathLearningFixture();
    final lesson = original
        .edit(
          blocks: [
            for (final block in original.blocks)
              MathTextbookBlock.fromJson({
                ...block.toJson(),
                'sourceLayout': true,
              }),
          ],
          learning: MathTextbookLearning.fromJson({
            ...original.learning!.toJson(),
            'exercises': [
              {
                ...original.learning!.exercises.single.toJson(),
                'blockIds': ['exercise', 'example'],
              },
            ],
          }),
        )
        .approve(
          pdfSha256: book.pdfSha256,
          reviewer: '家长',
          editingMilliseconds: 0,
        );
    courses.current = courses.current!.replace(lessons: [lesson]);
    final saved = courses.current!.toJson();
    await mount(
      tester,
      MathTextbookLearningEditorPage(
        book: book,
        lesson: lesson,
        section: MathTextbookLearningSection.exercises,
      ),
    );
    await tester.tap(find.text('原书第1题'));
    await settleMathTextbookImages(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<MathTextbookStudyContent>(
            find.byType(MathTextbookStudyContent),
          )
          .map((widget) => widget.block.id),
      ['example', 'exercise'],
    );
    expect(
      tester
          .widgetList<MathTextbookSourcePreview>(
            find.byType(MathTextbookSourcePreview),
          )
          .map((widget) => (widget.book.pdfSha256, widget.source.page)),
      [(book.pdfSha256, 1), (book.pdfSha256, 2)],
    );
    expect(find.byTooltip('打开原书'), findsOneWidget);
    await tester.tap(find.text('查看文字').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('把2个圆和3个圆合在一起'), findsOneWidget);
    await visible(tester, find.text('你的答案'));
    await tester.tap(find.text('你的答案'));
    await settleMathTextbookImages(tester);
    expect(find.text('编辑作答项'), findsOneWidget);
    expect(
      tester
          .widgetList<MathTextbookStudyContent>(
            find.byType(MathTextbookStudyContent),
          )
          .map((widget) => widget.block.id),
      ['example', 'exercise'],
    );
    await visible(tester, input('确定的答案'));
    expect(tester.widget<TextField>(input('确定的答案')).controller!.text, '5');
    expect(courses.current!.toJson(), saved);
    expect(courses.saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('知识点编辑页展示原书图示，空摘要也能对照完整来源', (tester) async {
    final original = mathLearningFixture();
    final lesson = original.edit(
      blocks: [
        for (final block in original.blocks)
          MathTextbookBlock.fromJson({...block.toJson(), 'sourceLayout': true}),
      ],
      learning: MathTextbookLearning.fromJson({
        ...original.learning!.toJson(),
        'knowledgePoints': [
          {
            ...original.learning!.knowledgePoints.single.toJson(),
            'summary': '',
          },
        ],
      }),
    );
    final saved = courses.current!.toJson();
    await mount(
      tester,
      MathTextbookLearningEditorPage(
        book: book,
        lesson: lesson,
        section: MathTextbookLearningSection.knowledge,
      ),
    );
    await tester.tap(find.text('合并数量'));
    await settleMathTextbookImages(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<MathTextbookStudyContent>(
            find.byType(MathTextbookStudyContent),
          )
          .map((widget) => widget.block.id),
      ['example'],
    );
    expect(
      tester
          .widgetList<MathTextbookSourcePreview>(
            find.byType(MathTextbookSourcePreview),
          )
          .map((widget) => widget.source.page),
      [1],
    );
    expect(find.byTooltip('打开原书'), findsOneWidget);
    await tester.tap(find.text('查看文字'));
    await tester.pumpAndSettle();
    expect(find.textContaining('把2个圆和3个圆合在一起'), findsOneWidget);
    await visible(tester, input('知识要点（按原书补齐）'));
    expect(tester.widget<TextField>(input('知识要点（按原书补齐）')).controller!.text, '');
    expect(courses.current!.toJson(), saved);
    expect(courses.saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('更换题组关联后预览立即更新，应用这一项仍不写入课时', (tester) async {
    final lesson = mathLearningFixture();
    final saved = courses.current!.toJson();
    await mount(
      tester,
      MathTextbookLearningEditorPage(
        book: book,
        lesson: lesson,
        section: MathTextbookLearningSection.exercises,
      ),
    );
    await tester.tap(find.text('原书第1题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 + 3 = ?'), findsOneWidget);
    await tester.tap(find.text('关联原书内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<MathTextbookStudyContent>(
            find.byType(MathTextbookStudyContent),
          )
          .map((widget) => widget.block.id),
      ['example'],
    );
    expect(find.textContaining('把2个圆和3个圆合在一起'), findsOneWidget);
    expect(find.textContaining('2 + 3 = ?'), findsNothing);
    await visible(tester, find.text('应用这一项'));
    await tester.tap(find.text('应用这一项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原书第1题'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<MathTextbookStudyContent>(
            find.byType(MathTextbookStudyContent),
          )
          .map((widget) => widget.block.id),
      ['example'],
    );
    expect(courses.current!.toJson(), saved);
    expect(courses.saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('学习配置未补齐也能完成内容审核，重新打开保留结果', (tester) async {
    final source = mathLearningFixture();
    final pending = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {
        ...source.learning!.toJson(),
        'coverageConfirmed': false,
        'practicePlans': <Object>[],
      },
    });
    courses.current = MathTextbookCourse.forBook(book)
        .replace(lessons: [pending]);
    await mount(
      tester,
      MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: pending.id),
    );
    await visible(tester, find.text('核对完成，审核本课'));
    await tester.tap(find.text('核对完成，审核本课'));
    await tester.pumpAndSettle();
    await tester.enterText(input('审核人称呼'), '测试妈妈');
    final checks = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Checkbox),
    );
    expect(checks, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      await tester.tap(checks.at(i));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('确认审核并保存'));
    await tester.pumpAndSettle();
    final saved = courses.current!.lessons.single;
    expect(courses.saves, 1);
    expect(saved.isApproved(book.pdfSha256), isTrue);
    expect(saved.learning!.coverageConfirmed, isFalse);
    expect(saved.learning!.checkReady, throwsFormatException);
    await mount(
      tester,
      MathTextbookLessonPage(
        key: UniqueKey(),
        bookId: book.pdfSha256,
        lessonId: saved.id,
      ),
    );
    expect(find.textContaining('已通过'), findsOneWidget);
    expect(courses.current!.lessons.single.review!.reviewer, '测试妈妈');
  });

  testWidgets('扫描版无课程时不自动整理，并显示原书阅读入口', (tester) async {
    courses.current = null;
    await mount(
      tester,
      MathTextbookReviewPage(bookId: book.pdfSha256),
      knownCatalog: true,
      courseGenerationSupported: false,
    );
    expect(generator.bookCalls, 0);
    expect(
      find.text('课时学习暂未开放'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .join(' | '),
    );
    expect(find.text('阅读原书'), findsOneWidget);
    expect(find.text('继续整理'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('扫描版已有课程可保留查看，但隐藏重新整理入口', (tester) async {
    courses.current = courses.current!.replace(
      outline: MathTextbookCourseOutline(
        source: 'bookmarks',
        organizationVersion: 1,
        ranges: const [
          MathTextbookCourseRange(title: '自有分数课', startPage: 1, endPage: 2),
        ],
        completedLessonIds: const ['math-1-2'],
      ),
    );
    await mount(
      tester,
      MathTextbookReviewPage(bookId: book.pdfSha256),
      knownCatalog: true,
      courseGenerationSupported: false,
    );
    expect(find.text('自有分数课'), findsOneWidget);
    expect(generator.bookCalls, 0);
    expect(find.text('继续整理'), findsNothing);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('重新整理原书'), findsNothing);
    expect(find.text('整理一个完整课时'), findsNothing);
    expect(find.text('查看原书目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('扫描版数学学习无课程时明确引导阅读原书', (tester) async {
    courses.current = null;
    await mount(
      tester,
      MathTextbookBookPage(bookId: book.pdfSha256),
      knownCatalog: true,
      courseGenerationSupported: false,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MathTextbookBookPage)),
    );
    await container.read(textbookCatalogProvider.future);
    expect(
      await container.read(mathTextbookCourseProvider(book.pdfSha256).future),
      isNull,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('课时学习暂未开放'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .join(' | '),
    );
    expect(find.text('阅读原书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('${width}dp 大字首次自动整理，逐课显示并按保存进度续接', (tester) async {
      courses.current = null;
      final gate = Completer<void>();
      generator.bookGate = gate;
      final page = MathTextbookReviewPage(bookId: book.pdfSha256);
      await mount(
        tester,
        page,
        size: Size(width, 860),
        scale: 2,
        knownCatalog: true,
        settle: false,
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find
            .byKey(const ValueKey('math-review-lesson-math-1-2'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(generator.bookCalls, 1);
      expect(find.text('内容审核'), findsOneWidget);
      expect(find.text('整理一个完整课时'), findsNothing);
      expect(find.text('第一单元'), findsOneWidget);
      expect(find.text('第二单元'), findsOneWidget);
      expect(find.text('自有第一课'), findsOneWidget);
      expect(find.text('自有第二课'), findsOneWidget);
      expect(find.text('待整理'), findsOneWidget);
      expect(courses.current!.lessons, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('暂停整理'));
      gate.complete();
      await tester.pumpAndSettle();
      expect(courses.current!.outline!.completedLessonIds, ['math-1-2']);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(
        tester,
        page,
        size: Size(width, 860),
        scale: 2,
        knownCatalog: true,
      );
      expect(generator.bookCalls, 1);
      await tester.tap(find.text('继续整理'));
      await tester.pumpAndSettle();
      expect(generator.bookCalls, 2);
      expect(courses.current!.lessons, hasLength(2));
      expect(find.text('继续整理'), findsNothing);
      expect(find.text('自有第二课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final knownCatalog in [true, false]) {
    testWidgets('已有旧版草稿进入审核页仍尝试更新一次（已核验书目：$knownCatalog）', (tester) async {
      courses.current = courses.current!.replace(
        outline: MathTextbookCourseOutline(
          source: 'bookmarks',
          ranges: const [
            MathTextbookCourseRange(title: '自有旧课', startPage: 1, endPage: 2),
          ],
          completedLessonIds: const ['math-1-2'],
        ),
      );
      await mount(
        tester,
        MathTextbookReviewPage(bookId: book.pdfSha256),
        knownCatalog: knownCatalog,
      );
      expect(generator.bookCalls, knownCatalog ? 1 : 0);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MathTextbookReviewPage)),
      );
      container.invalidate(mathTextbookCourseProvider(book.pdfSha256));
      await tester.pumpAndSettle();
      expect(
        generator.bookCalls,
        knownCatalog ? 1 : 0,
        reason: '课程刷新不应重复启动同一次更新',
      );
    });
  }

  testWidgets('离开审核页编辑时不在后台重整，返回审核页后才更新旧草稿', (tester) async {
    courses.current = courses.current!.replace(
      outline: MathTextbookCourseOutline(
        source: 'bookmarks',
        organizationVersion: mathTextbookOrganizationVersion,
        ranges: const [
          MathTextbookCourseRange(title: '自有旧课', startPage: 1, endPage: 2),
        ],
        completedLessonIds: const ['math-1-2'],
      ),
    );
    await mount(
      tester,
      MathTextbookReviewPage(bookId: book.pdfSha256),
      knownCatalog: true,
    );
    expect(generator.bookCalls, 0);
    final element = tester.element(find.byType(MathTextbookReviewPage));
    final container = ProviderScope.containerOf(element, listen: false);
    final navigator = Navigator.of(element);
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('当前题目正在编辑')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    courses.current = courses.current!.replace(
      outline: MathTextbookCourseOutline.fromJson({
        ...courses.current!.outline!.toJson(),
        'organizationVersion': 1,
      }),
    );
    container.invalidate(mathTextbookCourseProvider(book.pdfSha256));
    await tester.pumpAndSettle();
    expect(find.text('当前题目正在编辑'), findsOneWidget);
    expect(generator.bookCalls, 0);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(generator.bookCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧大范围课时单独保留对照，不混进当前目录和审核计数', (tester) async {
    final old = mathLessonFixture(title: '原来的大课时');
    courses.current = MathTextbookCourse.forBook(book).replace(
      lessons: [
        old,
        mathLessonFixture(title: '第一课', end: 1),
        mathLessonFixture(title: '第二课', start: 2, end: 3),
      ],
      outline: MathTextbookCourseOutline(
        source: 'text',
        organizationVersion: mathTextbookOrganizationVersion,
        ranges: const [
          MathTextbookCourseRange(title: '第一课', startPage: 1, endPage: 1),
          MathTextbookCourseRange(title: '第二课', startPage: 2, endPage: 3),
        ],
        retainedLessonIds: [old.id],
      ),
    );
    await mount(tester, MathTextbookReviewPage(bookId: book.pdfSha256));
    expect(
      find.byKey(const ValueKey('math-review-lesson-math-1-2')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('math-retained-lesson-math-1-2')),
      findsOneWidget,
    );
    expect(find.text('保留的原课时'), findsOneWidget);
    expect(find.textContaining('0/3 课已通过'), findsNothing);
    expect(find.textContaining('0/2 课已通过'), findsWidgets);
    expect(courses.current!.lessons.first.toJson(), old.toJson());
  });

  testWidgets('课时按类别进入核对，未改内容保留审核，原页编辑返回不丢修改', (tester) async {
    final lesson = mathLearningFixture().approve(
      pdfSha256: book.pdfSha256,
      reviewer: '家长',
      editingMilliseconds: 0,
      at: DateTime.utc(2026, 11, 14),
    );
    courses.current = courses.current!.replace(lessons: [lesson]);
    await mount(
      tester,
      MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: lesson.id),
      size: const Size(320, 860),
      scale: 2,
    );
    expect(input('课时名称'), findsNothing);
    expect(find.text('知识点 · 1'), findsOneWidget);
    expect(find.text('教材原题与题组 · 1'), findsOneWidget);
    expect(find.text('本课巩固 · 1'), findsOneWidget);
    await visible(tester, find.text('合并数量'));
    await tester.tap(find.text('合并数量'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input('知识点名称')).controller!.text, '合并数量');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('原书范围与待整理内容'), findsOneWidget);
    await visible(tester, find.text('知识点 · 1'));
    await tester.tap(find.widgetWithText(TextButton, '添加').first);
    await tester.pumpAndSettle();
    expect(input('知识点名称'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('知识点'), findsOneWidget);
    expect(find.textContaining('教材原题与题组'), findsNothing);
    expect(input('所属单元'), findsNothing);
    final addKnowledge = find.byTooltip('添加知识点');
    expect(addKnowledge.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(addKnowledge).dx, greaterThan(160));
    await tester.tap(addKnowledge);
    await tester.pumpAndSettle();
    expect(input('知识点名称'), findsOneWidget);
    expect(input('知识要点（按原书补齐）'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await visible(tester, find.text('应用到课时草稿'));
    await tester.tap(find.text('应用到课时草稿'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有未保存修改'), findsNothing);
    await openSource(tester);
    await tester.enterText(input('课时名称'), '按类别核对后的课时');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('按类别核对后的课时'), findsOneWidget);
    expect(find.textContaining('有未保存修改'), findsOneWidget);
    await visible(tester, find.text('保存草稿'));
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.title, '按类别核对后的课时');
    expect(
      courses.current!.lessons.single.learning!.exercises.single.toJson(),
      lesson.learning!.exercises.single.toJson(),
    );
    expect(courses.current!.lessons.single.review, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容审核中每个知识点都直接打开对应条目的编辑表单', (tester) async {
    final original = mathLearningFixture();
    final points = [
      {
        ...original.learning!.knowledgePoints.single.toJson(),
        'title': '第一个知识点',
      },
      {
        'id': 'kp-2',
        'title': '第二个知识点',
        'summary': '第二个知识点的说明。',
        'blockIds': ['example'],
      },
      {
        'id': 'kp-3',
        'title': '第三个知识点',
        'summary': '第三个知识点的说明。',
        'blockIds': ['example'],
      },
    ];
    final lesson = original.edit(
      learning: MathTextbookLearning.fromJson({
        ...original.learning!.toJson(),
        'knowledgePoints': points,
      }),
    );
    courses.current = courses.current!.replace(lessons: [lesson]);
    await mount(
      tester,
      MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: lesson.id),
    );

    for (final (id, title) in [
      ('kp', '第一个知识点'),
      ('kp-2', '第二个知识点'),
      ('kp-3', '第三个知识点'),
    ]) {
      final row = find.byKey(ValueKey('math-lesson-content-$id'));
      await visible(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final titleField = input('知识点名称');
      expect(tester.widget<TextField>(titleField).controller!.text, title);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('知识点名称'), findsNothing);
      expect(find.text('原书范围与待整理内容'), findsOneWidget);
      expect(find.text('知识点 · 3'), findsOneWidget);
    }

    expect(courses.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从审核详情直达知识点表单，应用后直接返回并更新课时草稿', (tester) async {
    final original = mathLearningFixture();
    final lesson = original.edit(
      learning: MathTextbookLearning.fromJson({
        ...original.learning!.toJson(),
        'knowledgePoints': [
          for (final point in original.learning!.knowledgePoints)
            point.toJson(),
          {
            'id': 'kp-second',
            'title': '待修改知识点',
            'summary': '用于验证直接应用后的返回。',
            'blockIds': ['example'],
          },
        ],
      }),
    );
    courses.current = courses.current!.replace(lessons: [lesson]);
    await mount(
      tester,
      MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: lesson.id),
    );

    final row = find.byKey(const ValueKey('math-lesson-content-kp-second'));
    await visible(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(input('知识点名称'), '已应用的知识点');
    await tester.tap(find.text('应用这一项'));
    await tester.pumpAndSettle();

    expect(find.text('已应用的知识点'), findsOneWidget);
    expect(find.text('知识点名称'), findsNothing);
    expect(find.text('原书范围与待整理内容'), findsOneWidget);
    expect(find.textContaining('有未保存修改'), findsOneWidget);
    expect(courses.saves, 0);
    expect(tester.takeException(), isNull);
  });

  for (final width in [420.0, 320.0]) {
    testWidgets('长列表底部应用按钮保持可点击并完整保存修改（宽度：$width）', (tester) async {
      final original = mathLearningFixture();
      final points = [
        ...original.learning!.knowledgePoints,
        for (var i = 1; i <= 24; i++)
          MathTextbookKnowledgePoint(
            id: 'extra-$i',
            title: '追加知识点$i',
            summary: '对照本课原书核对第$i项知识内容。',
            blockIds: ['example'],
          ),
      ];
      final lesson = original
          .edit(
            learning: MathTextbookLearning.fromJson({
              ...original.learning!.toJson(),
              'knowledgePoints': points.map((point) => point.toJson()).toList(),
              'coverageConfirmed': false,
            }),
          )
          .approve(
            pdfSha256: book.pdfSha256,
            reviewer: '家长',
            editingMilliseconds: 0,
            at: DateTime.utc(2026, 11, 14),
          );
      courses.current = courses.current!.replace(lessons: [lesson]);
      final narrow = width == 320;
      await mount(
        tester,
        MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: lesson.id),
        size: Size(width, 640),
        scale: narrow ? 2 : 1,
      );
      await openSource(tester);
      await visible(tester, find.text('知识点、教材原题与本课巩固'));
      await tester.tap(find.text('知识点、教材原题与本课巩固'));
      await tester.pumpAndSettle();
      if (narrow) {
        await tester.enterText(input('所属单元'), '固定底部的测试单元');
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
      }
      final apply = find.widgetWithText(FilledButton, '应用到课时草稿');
      final beforeScroll = tester.getRect(apply);
      expect(apply.hitTestable(), findsOneWidget);
      expect(beforeScroll.bottom, lessThanOrEqualTo(narrow ? 440 : 640));
      final viewport = tester.getRect(find.byType(Scrollable).first);
      expect(viewport.height, greaterThan(0));
      expect(viewport.bottom, lessThanOrEqualTo(beforeScroll.top));
      await visible(tester, find.byTooltip('移除追加知识点24'));
      expect(tester.getRect(apply), beforeScroll);
      expect(apply.hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('移除追加知识点24'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('移除追加知识点24'), findsNothing);
      expect(tester.getRect(apply), beforeScroll);
      expect(apply.hitTestable(), findsOneWidget);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(courses.saves, 0);
      expect(courses.current!.lessons.single.toJson(), lesson.toJson());
      await visible(tester, find.text('保存草稿'));
      await tester.tap(find.text('保存草稿'));
      await tester.pumpAndSettle();
      final saved = courses.current!.lessons.single;
      expect(saved.learning!.toJson(), {
        ...original.learning!.toJson(),
        'unitTitle': narrow ? '固定底部的测试单元' : original.learning!.unitTitle,
        'knowledgePoints': points
            .take(points.length - 1)
            .map((point) => point.toJson())
            .toList(),
        'coverageConfirmed': false,
      });
      expect(saved.isApproved(book.pdfSha256), isFalse);
      expect(courses.saves, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320dp 双倍字号下可填写范围、整理并进入待核列表', (tester) async {
    courses.current = null;
    await mount(
      tester,
      MathTextbookReviewPage(bookId: book.pdfSha256),
      size: const Size(320, 640),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await visible(tester, find.text('整理一个完整课时'));
    await tester.tap(find.text('整理一个完整课时'));
    await tester.pumpAndSettle();
    await tester.enterText(input('课时名称'), '自有完整小节');
    await tester.enterText(input('起始 PDF 页'), '1');
    await tester.enterText(input('结束 PDF 页'), '2');
    await tester.tap(find.text('开始整理'));
    await tester.pumpAndSettle();
    expect(generator.calls, 1);
    expect(courses.current!.lessons.single.startPage, 1);
    expect(courses.current!.lessons.single.endPage, 2);
    await visible(tester, find.text('自有完整小节'));
    expect(find.textContaining('待家长核对'), findsNothing);
    expect(find.textContaining('PDF 第'), findsNothing);
    final unit = find.byKey(const ValueKey('math-review-unit-待确认归属的内容'));
    final more = find.descendant(
      of: unit,
      matching: find.byIcon(Icons.more_vert),
    );
    final summary = find.descendant(of: unit, matching: find.text('0/1 课已通过'));
    await visible(tester, more, delta: -300);
    expect(
      tester.getCenter(more).dx,
      greaterThan(tester.getCenter(summary).dx),
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('选择课时'), findsNothing);
    expect(find.text('重新整理此课'), findsOneWidget);
    expect(find.text('移除课时区间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无单元归属的一级目录条目与审核分组左边缘对齐', (tester) async {
    final reviewBook = mathTextbookFixture(pages: 4);
    final course = MathTextbookCourse.forBook(reviewBook).replace(
      outline: MathTextbookCourseOutline(
        source: 'text',
        organizationVersion: mathTextbookOrganizationVersion,
        ranges: const [
          MathTextbookCourseRange(title: '1～6 的表内乘法', startPage: 1, endPage: 1),
          MathTextbookCourseRange(
            title: '7～9 的表内乘、除法',
            startPage: 2,
            endPage: 2,
          ),
          MathTextbookCourseRange(
            title: '第一单元',
            unitTitle: '第一单元',
            startPage: 3,
            endPage: 3,
          ),
          MathTextbookCourseRange(
            title: '第一课',
            unitTitle: '第一单元',
            startPage: 4,
            endPage: 4,
          ),
        ],
      ),
    );
    await mount(
      tester,
      Scaffold(
        body: MathTextbookReviewContent(
          book: reviewBook,
          course: course,
          progress: const SizedBox.shrink(),
          running: false,
          onLesson: (_) {},
          onUnitActions: (_) {},
          onBookReview: () {},
        ),
      ),
    );

    final unassignedHeader = find.text('待确认归属的内容');
    final headerLeft = tester.getTopLeft(unassignedHeader).dx;
    for (final title in ['1～6 的表内乘法', '7～9 的表内乘、除法']) {
      expect(tester.getTopLeft(find.text(title)).dx, closeTo(headerLeft, .01));
    }
    final unitHeader = find.text('第一单元');
    final childLesson = find.text('第一课');
    expect(
      tester.getTopLeft(childLesson).dx,
      greaterThan(tester.getTopLeft(unitHeader).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('待比较大纲显示新标题和单元归属，同时标出保留的旧稿', (tester) async {
    final reviewBook = mathTextbookFixture(pages: 1);
    final base = mathLessonFixture(start: 1, end: 1, title: '～ 6 的表内乘法');
    final learning = seedMathTextbookLearning(base);
    MathTextbookLearning learningWithUnit(String unit) => MathTextbookLearning(
      unitTitle: unit,
      knowledgePoints: learning.knowledgePoints,
      exercises: learning.exercises,
      practicePlans: learning.practicePlans,
      coverageConfirmed: learning.coverageConfirmed,
      noExercises: learning.noExercises,
    );
    final current = base.edit(learning: learningWithUnit('旧单元'));
    final candidate = current.edit(
      title: '1～6 的表内乘法',
      learning: learningWithUnit(''),
    );
    final course = MathTextbookCourse.forBook(reviewBook).replace(
      lessons: [current],
      pendingLessons: [candidate],
      outline: MathTextbookCourseOutline(
        source: 'text',
        organizationVersion: mathTextbookOrganizationVersion,
        ranges: const [
          MathTextbookCourseRange(title: '1～6 的表内乘法', startPage: 1, endPage: 1),
        ],
      ),
    );
    await mount(
      tester,
      Scaffold(
        body: MathTextbookReviewContent(
          book: reviewBook,
          course: course,
          progress: const SizedBox.shrink(),
          running: false,
          onLesson: (_) {},
          onUnitActions: (_) {},
          onBookReview: () {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('math-review-unit-待确认归属的内容')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('math-review-unit-旧单元')), findsNothing);
    expect(find.text('1～6 的表内乘法'), findsOneWidget);
    expect(find.textContaining('当前草稿：～ 6 的表内乘法'), findsOneWidget);
    expect(find.textContaining('原单元：旧单元'), findsOneWidget);
    expect(find.textContaining('有新整理结果待比较'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final largeText in [false, true]) {
    testWidgets('同名的单课单元合并后，课时入口与菜单分别响应（大字：$largeText）', (tester) async {
      const title = '100 以内的加法和减法（二）';
      final reviewBook = mathTextbookFixture(pages: 4);
      final lesson = mathLessonFixture(title: title);
      final course = MathTextbookCourse.forBook(reviewBook).replace(
        lessons: [
          lesson,
          mathLessonFixture(title: '原书练习', start: 3, end: 3),
        ],
        pendingLessons: [lesson.edit(title: '待比较的新稿')],
        outline: MathTextbookCourseOutline(
          source: 'bookmarks',
          organizationVersion: mathTextbookOrganizationVersion,
          completedLessonIds: [lesson.id],
          ranges: const [
            MathTextbookCourseRange(
              title: title,
              unitTitle: title,
              startPage: 1,
              endPage: 2,
            ),
            MathTextbookCourseRange(
              title: '原书练习',
              unitTitle: '第二单元',
              startPage: 3,
              endPage: 3,
            ),
            MathTextbookCourseRange(
              title: '待整理课时',
              unitTitle: '待整理单元',
              startPage: 4,
              endPage: 4,
            ),
          ],
        ),
      );
      final opened = <String>[];
      final actions = <List<String>>[];
      await mount(
        tester,
        Scaffold(
          body: MathTextbookReviewContent(
            book: reviewBook,
            course: course,
            progress: const SizedBox.shrink(),
            running: false,
            onLesson: (lesson) => opened.add(lesson.id),
            onUnitActions: (lessons) =>
                actions.add(lessons.map((lesson) => lesson.id).toList()),
            onBookReview: () {},
          ),
        ),
        size: Size(largeText ? 320 : 420, 640),
        scale: largeText ? 2 : 1,
      );
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining('有新整理结果待比较'), findsOneWidget);
      final unit = find.byKey(const ValueKey('math-review-unit-$title'));
      final more = find.descendant(
        of: unit,
        matching: find.byTooltip('课时更多操作'),
      );
      final summary = find.descendant(
        of: unit,
        matching: find.text('0/1 课已通过'),
      );
      final icon = find.descendant(
        of: unit,
        matching: find.byIcon(Icons.more_vert),
      );
      expect(
        tester.getCenter(more).dx,
        greaterThan(tester.getCenter(summary).dx),
      );
      for (final other in ['第二单元', '待整理单元']) {
        final header = find.byKey(ValueKey('math-review-unit-$other'));
        expect(
          tester
              .getRect(
                find.descendant(
                  of: header,
                  matching: find.byIcon(Icons.more_vert),
                ),
              )
              .right,
          closeTo(tester.getRect(icon).right, .01),
        );
        expect(
          tester
              .getRect(
                find.descendant(of: header, matching: find.text('0/1 课已通过')),
              )
              .right,
          closeTo(tester.getRect(summary).right, .01),
        );
      }
      final arrow = find.descendant(
        of: find.byKey(const ValueKey('math-review-lesson-math-3-3')),
        matching: find.byIcon(Icons.chevron_right),
      );
      expect(
        tester.getRect(arrow).right,
        closeTo(tester.getRect(icon).right, .01),
      );
      await tester.tap(find.text('待比较的新稿'));
      await tester.pumpAndSettle();
      expect(opened, [lesson.id]);
      expect(actions, isEmpty);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(actions, [
        [lesson.id],
      ]);
      expect(opened, [lesson.id]);
      await tester.tap(summary);
      await tester.pumpAndSettle();
      expect(actions, [
        [lesson.id],
        [lesson.id],
      ]);
      expect(opened, [lesson.id]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('多课单元的同名课只显示一次，菜单仍可整理第二课', (tester) async {
    courses.current = MathTextbookCourse.forBook(book).replace(
      lessons: [
        mathLessonFixture(title: '第一课'),
        mathLessonFixture(title: '第二课', start: 3, end: 3),
      ],
      outline: MathTextbookCourseOutline(
        source: 'bookmarks',
        organizationVersion: mathTextbookOrganizationVersion,
        completedLessonIds: const ['math-1-2', 'math-3-3'],
        ranges: const [
          MathTextbookCourseRange(
            title: '第一课',
            unitTitle: '第一课',
            startPage: 1,
            endPage: 2,
          ),
          MathTextbookCourseRange(
            title: '第二课',
            unitTitle: '第一课',
            startPage: 3,
            endPage: 3,
          ),
        ],
      ),
    );
    final original = courses.current!.toJson();
    await mount(
      tester,
      MathTextbookReviewPage(bookId: book.pdfSha256),
      size: const Size(320, 640),
      scale: 2,
    );
    expect(find.text('第一课'), findsOneWidget);
    expect(find.text('第二课'), findsOneWidget);
    final more = find.descendant(
      of: find.byKey(const ValueKey('math-review-unit-第一课')),
      matching: find.byIcon(Icons.more_vert),
    );
    await visible(tester, more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('选择课时'), findsOneWidget);
    final selected = find.byKey(const ValueKey('math-review-actions-math-3-3'));
    await tester.ensureVisible(selected);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新整理此课'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input('课时名称')).controller!.text, '第二课');
    expect(tester.widget<TextField>(input('起始 PDF 页')).controller!.text, '3');
    expect(tester.widget<TextField>(input('结束 PDF 页')).controller!.text, '3');
    expect(courses.current!.toJson(), original);
    expect(generator.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败保留输入，重试后重新打开恢复；审核后修改使审核失效', (tester) async {
    final page = MathTextbookLessonPage(
      bookId: book.pdfSha256,
      lessonId: 'math-1-2',
    );
    await mount(tester, page);
    await openSource(tester);
    await tester.enterText(input('课时名称'), '家长修订的完整课');
    courses.failSave = true;
    await visible(tester, find.text('保存草稿'));
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    expect(find.text('课时未保存，修改内容保留，请重试'), findsOneWidget);
    expect(courses.current!.lessons.single.title, '自有分数课');
    courses.failSave = false;
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.title, '家长修订的完整课');
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, page);
    await openSource(tester);
    expect(
      tester.widget<TextField>(input('课时名称')).controller!.text,
      '家长修订的完整课',
    );
    await visible(tester, find.text('核对完成，审核本课'));
    await tester.tap(find.text('核对完成，审核本课'));
    await tester.pumpAndSettle();
    await tester.enterText(input('审核人称呼'), '测试妈妈');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(Checkbox).at(i));
      await tester.pump();
    }
    await tester.tap(find.text('确认审核并保存'));
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.isApproved(book.pdfSha256), isTrue);
    expect(courses.current!.lessons.single.review!.reviewer, '测试妈妈');
    await visible(tester, input('课时名称'), delta: -400);
    await tester.enterText(input('课时名称'), '再次修订');
    await visible(tester, find.text('保存草稿'));
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.review, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存期间重复点击只写一次，锁定后迟到保存失败', (tester) async {
    await mount(
      tester,
      MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: 'math-1-2'),
    );
    await openSource(tester);
    await tester.enterText(input('课时名称'), '不能迟到写入');
    courses.saveGate = Completer<void>();
    await visible(tester, find.text('保存草稿'));
    await tester.tap(find.text('保存草稿'));
    await tester.tap(find.text('保存草稿'));
    await tester.pump();
    expect(courses.saves, 1);
    lockParentForTesting();
    courses.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.title, '自有分数课');
    expect(tester.takeException(), isNull);
  });

  testWidgets('原书对照编辑可应用到课时，返回时提示未保存修改', (tester) async {
    await mount(
      tester,
      MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: 'math-1-2'),
    );
    await openSource(tester);
    await tester.tap(find.text('对照原书并修改').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await settleMathTextbookImages(tester);
    await visible(tester, input('文字内容'));
    await tester.enterText(input('文字内容'), '家长补齐的文字');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃这处修改？'), findsOneWidget);
    await tester.tap(find.text('继续修改'));
    await tester.pumpAndSettle();
    await visible(tester, find.text('应用修改'));
    await tester.tap(find.text('应用修改'));
    await tester.pumpAndSettle();
    await visible(tester, find.text('保存草稿'));
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.blocks.first.text, '家长补齐的文字');
    expect(
      courses.current!.lessons.single.blocks.where(
        (b) => b.kind == MathTextbookBlockKind.sourcePage,
      ),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('新旧结果可展开原书对照，取消采纳保留审核，确认后采用新稿', (tester) async {
    final saved = mathLessonFixture().approve(
      pdfSha256: book.pdfSha256,
      reviewer: '测试家长',
      editingMilliseconds: 0,
      at: DateTime.utc(2026, 11, 13),
    );
    courses.current = courses.current!.replace(
      lessons: [saved],
      pendingLessons: [saved.edit(title: '重整课名')],
    );
    await mount(
      tester,
      MathTextbookLessonPage(bookId: book.pdfSha256, lessonId: saved.id),
    );
    await tester.tap(find.text('比较新整理结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开原书对照').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await settleMathTextbookImages(tester);
    expect(find.byType(MathTextbookSourcePreview), findsOneWidget);
    await tester.tap(find.text('新整理结果'));
    await tester.pumpAndSettle();
    expect(find.text('重整课名'), findsOneWidget);
    await tester.tap(find.text('采纳新整理结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.isApproved(book.pdfSha256), isTrue);
    await tester.tap(find.text('采纳新整理结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认采纳'));
    await tester.pumpAndSettle();
    expect(courses.current!.lessons.single.title, '重整课名');
    expect(courses.current!.lessons.single.review, isNull);
    expect(courses.current!.pendingLessons, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('公式表单修改后仍保留三行竖式和对应进位', (tester) async {
    final initial = MathTextbookVerticalAddition(
      ['541', '267', '808'],
      [const MathTextbookCarry(1, 1), const MathTextbookCarry(1, 2)],
    );
    MathTextbookExpression? result;
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<MathTextbookExpression>(
                context: context,
                builder: (_) => MathTextbookExpressionDialog(initial: initial),
              );
            },
            child: const Text('编辑测试公式'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑测试公式'));
    await tester.pumpAndSettle();
    expect(find.text('公式暂无法显示，请查看原书'), findsNothing);
    await tester.enterText(input('第一行'), '542');
    await tester.enterText(input('横线下的结果'), '809');
    await tester.tap(find.text('使用此公式'));
    await tester.pumpAndSettle();
    expect((result as MathTextbookVerticalAddition).rows, [
      '542',
      '267',
      '809',
    ]);
    expect(
      (result as MathTextbookVerticalAddition).carries
          .map((c) => (c.value, c.columnFromRight))
          .toSet(),
      {(1, 1), (1, 2)},
    );
    expect(tester.takeException(), isNull);
  });

  for (final (size, initial) in [
    (
      const Size(320, 640),
      MathTextbookVerticalArithmetic(
        ['36', '19', '17'],
        operation: '-',
        annotations: const [
          MathTextbookVerticalAnnotation(
            value: '2',
            row: 0,
            columnFromRight: 1,
          ),
          MathTextbookVerticalAnnotation(
            value: '16',
            row: 0,
            columnFromRight: 0,
          ),
          MathTextbookVerticalAnnotation(
            value: '.',
            row: 0,
            columnFromRight: 1,
            level: 1,
          ),
        ],
      ),
    ),
    (
      const Size(420, 860),
      MathTextbookVerticalArithmetic(['35', ' 2', ' 7'], operation: '+'),
    ),
  ]) {
    testWidgets('竖式表单在$size保留空位、借位及标注层次', (tester) async {
      MathTextbookExpression? result;
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<MathTextbookExpression>(
                  context: context,
                  builder: (_) =>
                      MathTextbookExpressionDialog(initial: initial),
                );
              },
              child: const Text('编辑测试公式'),
            ),
          ),
        ),
        size: size,
        scale: 2,
      );
      await tester.tap(find.text('编辑测试公式'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('横线下的结果')).controller!.text,
        initial.rows[2],
      );
      await visible(tester, find.text('排版预览'), delta: 200);
      expect(find.text('公式暂无法显示，请查看原书'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('使用此公式'));
      await tester.pumpAndSettle();
      expect(result!.toJson(), initial.toJson());
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 640), const Size(1000, 500)]) {
    testWidgets('二维公式和原书对照适应 $size 大字号布局', (tester) async {
      final block = MathTextbookBlock(
        id: 'formula',
        kind: MathTextbookBlockKind.formula,
        spans: [
          const MathTextbookSpan.text('面积与体积：'),
          const MathTextbookSpan.math(
            MathTextbookFraction('123456789012', '999999999999'),
          ),
          const MathTextbookSpan.text('平方厘米，'),
          const MathTextbookSpan.math(MathTextbookPower('cm', 3)),
        ],
        sources: const [
          MathTextbookRegion(page: 1, left: .1, top: .1, right: .8, bottom: .5),
        ],
      );
      await mount(
        tester,
        MathTextbookBlockEditorPage(
          book: book,
          block: block,
          startPage: 1,
          endPage: 2,
        ),
        size: size,
        scale: 2,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const ValueKey('math-span-1')));
      expect(find.text('公式暂无法显示，请查看原书'), findsNothing);
      expect(tester.takeException(), isNull);
      await visible(tester, find.text('应用修改'));
      expect(tester.takeException(), isNull);
    });
  }
}
