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
import 'package:poemath/features/textbook/math_textbook_block_editor_page.dart';
import 'package:poemath/features/textbook/math_textbook_lesson_page.dart';
import 'package:poemath/features/textbook/math_textbook_review_page.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';
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
  setUp(() async {
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
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(420, 860),
    double scale = 1,
    bool knownCatalog = false,
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
          textbookFileServiceProvider.overrideWithValue(_Files()),
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
      await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openSource(WidgetTester tester) async {
    await visible(tester, find.text('原书范围与待整理内容'));
    await tester.tap(find.text('原书范围与待整理内容'));
    await tester.pumpAndSettle();
  }

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
    expect(find.text('知识点'), findsOneWidget);
    expect(find.textContaining('教材原题与题组'), findsNothing);
    expect(input('所属单元'), findsNothing);
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
    expect(find.textContaining('待家长核对'), findsOneWidget);
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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
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
    await tester.enterText(input('第一行加数'), '542');
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
