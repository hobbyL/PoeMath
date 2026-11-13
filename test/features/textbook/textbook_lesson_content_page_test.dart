import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';
import 'package:poemath/domain/textbook_text_display.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/exercise/exercise_providers.dart';
import 'package:poemath/features/textbook/exercise/textbook_exercise_overview.dart';
import 'package:poemath/features/textbook/textbook_detail_page.dart';
import 'package:poemath/features/textbook/textbook_lesson_content_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/textbook_writing_overview.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/textbook_page_number_fixture.dart';

class _Files extends TextbookFileService {
  @override
  Future<String?> installedPath(Textbook book) async => '/sample.pdf';
}

class _Books implements TextbookRepository {
  final recent = <String, String>{};
  @override
  Textbook? recentBook(String profileId) => find(recent[profileId] ?? '');
  @override
  Future<void> markOpened(String profileId, String id) async {
    recent[profileId] = id;
  }

  @override
  Stream<BoxEvent> watchReading(String profileId) => const Stream.empty();

  final saved = <int>[];
  @override
  Future<void> savePage(String profileId, Textbook book, int page) async =>
      saved.add(page);
  @override
  TextbookReading reading(String profileId, String id) =>
      const TextbookReading();
  @override
  List<Textbook> list() => [courseFixtureBook()];
  @override
  Textbook? find(String id) =>
      list().where((book) => book.pdfSha256 == id).firstOrNull;
  @override
  Future<void> addIfAbsent(Textbook book, {void Function()? authorize}) async {
    authorize?.call();
  }

  @override
  Future<void> setMatch(
    String profileId,
    String id,
    TextbookMatch match,
  ) async {}
  @override
  Future<void> delete(String id) async {}
}

class _Preview extends StatefulWidget {
  const _Preview({
    required this.options,
    required this.onCreate,
    required this.onDispose,
  });
  final TextbookViewerOptions options;
  final VoidCallback onCreate;
  final VoidCallback onDispose;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.options.onPageNumbersReady?.call(
        pageNumberFixture(pageCount: courseFixtureBook().pageCount),
      );
      widget.options.onReady(
        (page) async => widget.options.onPageChanged(page),
      );
    });
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  final book = courseFixtureBook();

  Future<void> pump(
    WidgetTester tester,
    TextbookContentSection section, {
    Map<String, dynamic>? raw,
    List<int> pages = const [2],
    Size size = const Size(360, 800),
    double scale = 1,
    Map<String, TextbookReadingLayout> readingLayouts = const {},
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookReadingLayoutProvider.overrideWith(
            (_, __) async => readingLayouts,
          ),
          textbookCourseProvider(book.pdfSha256).overrideWith(
            (_) async => TextbookCoursePack.fromJson(raw ?? courseFixture()),
          ),
          // 写一写字卡会读取笔顺资产与进度；测试固定为空资产/空进度，
          // 避免触达真实 Hive 与 2.4MB 资产。
          writingStrokeDataProvider.overrideWith(
            (_) async => const WritingStrokeAsset({}),
          ),
          textbookWritingProgressProvider(book.pdfSha256)
              .overrideWith((_) async => null),
          textbookExerciseProgressProvider(book.pdfSha256)
              .overrideWith((_) async => null),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: TextbookLessonContentPage(
            bookId: book.pdfSha256,
            section: section,
            pages: pages,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> withEmptyLesson() {
    final raw = courseFixture();
    final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
    (raw['lessons'] as List).insert(0, {
      ...lesson,
      'id': 'lesson-empty',
      'title': '故事共读',
      'lessonNumber': null,
      'sources': [courseFixtureSource(2), courseFixtureSource(3)],
      'coverage': {
        for (final category in TextbookCoursePack.categories)
          category: 'pending',
      },
      for (final category in TextbookCoursePack.categories)
        category: <Object?>[],
    });
    (((raw['units'] as List).single as Map)['lessonIds'] as List).insert(
      0,
      'lesson-empty',
    );
    return raw;
  }

  for (final pages in [
    [2],
    [2, 3],
  ]) {
    testWidgets('读一读有正文时不展示来源重叠的空课目（页=$pages）', (tester) async {
      await pump(
        tester,
        TextbookContentSection.reading,
        raw: withEmptyLesson(),
        pages: pages,
      );
      expect(find.widgetWithText(AppBar, '读一读·星月测试'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('textbook-content-lesson-001')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('textbook-content-lesson-empty')),
        findsNothing,
      );
      expect(find.text('故事共读'), findsNothing);
      expect(find.text('本课尚未整理课文与注音。'), findsNothing);
      expect(find.byTooltip('朗读课文'), findsOneWidget);
    });
  }

  testWidgets('读一读保留来源重叠且都有正文的多个课目', (tester) async {
    final raw = withEmptyLesson();
    final other = (raw['lessons'] as List).first as Map;
    other['paragraphs'] = [courseFixtureText('other-paragraph', '云山。', null)];
    await pump(tester, TextbookContentSection.reading, raw: raw);
    expect(find.widgetWithText(AppBar, '读一读'), findsOneWidget);
    expect(find.text('故事共读'), findsOneWidget);
    expect(find.text('星月测试'), findsOneWidget);
    expect(find.byType(TextbookCourseParagraphsContent), findsNWidgets(2));
    expect(find.text('本课尚未整理课文与注音。'), findsNothing);
  });

  for (final state in ['pending', 'notApplicable']) {
    testWidgets('读一读所有课目均无正文时保留真实空状态（$state）', (tester) async {
      final raw = courseFixture();
      final lesson = (raw['lessons'] as List).single as Map;
      lesson['paragraphs'] = <Object>[];
      lesson['recitations'] = <Object>[];
      (lesson['coverage'] as Map)['paragraphs'] = state;
      (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
      await pump(tester, TextbookContentSection.reading, raw: raw);
      expect(find.widgetWithText(AppBar, '读一读·星月测试'), findsOneWidget);
      expect(
        find.text(state == 'pending' ? '本课尚未整理课文与注音。' : '原书未要求本课阅读课文。'),
        findsOneWidget,
      );
      expect(find.byTooltip('朗读课文'), findsNothing);
    });
  }

  for (final scale in [1.0, 2.0]) {
    for (final poetry in [false, true]) {
      testWidgets('读一读接通诗行和空行分节，切换拼音保留结构（诗歌=$poetry，字号=$scale）', (
        tester,
      ) async {
        final raw = courseFixture();
        final lesson = (raw['lessons'] as List).single as Map;
        lesson['kind'] = poetry ? 'poetry' : 'text';
        lesson['paragraphs'] = [
          courseFixtureText('verse', '甲乙\n丙丁\n\n戊己\n庚辛', null),
        ];
        lesson['recitations'] = <Object>[];
        (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
        await pump(
          tester,
          TextbookContentSection.reading,
          raw: raw,
          size: const Size(1000, 1200),
          scale: scale,
        );
        for (final showPinyin in [false, true, false]) {
          final firstY = tester.getCenter(find.text('甲')).dy;
          final secondY = tester.getCenter(find.text('丙')).dy;
          final thirdY = tester.getCenter(find.text('戊')).dy;
          if (poetry) {
            expect(secondY, greaterThan(firstY));
            expect(thirdY - secondY, greaterThan(secondY - firstY));
          } else {
            expect(secondY, firstY);
            expect(thirdY, greaterThan(secondY));
          }
          expect(
            tester
                .widget<TextbookCourseParagraphsContent>(
                  find.byType(TextbookCourseParagraphsContent),
                )
                .showPinyin,
            showPinyin,
          );
          await tester.tap(find.byTooltip(showPinyin ? '隐藏拼音' : '显示拼音'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('普通text课目也使用原页恢复布局，不依赖课名或poetry标记', (tester) async {
    final raw = courseFixture();
    final lesson = (raw['lessons'] as List).single as Map;
    lesson['paragraphs'] = [courseFixtureText('legacy', '甲乙\n丙丁\n戊己', null)];
    lesson['recitations'] = <Object>[];
    (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
    await pump(
      tester,
      TextbookContentSection.reading,
      raw: raw,
      readingLayouts: const {
        'legacy': TextbookReadingLayout(
          breaks: {
            3: TextbookReadingBreak.line,
            6: TextbookReadingBreak.stanza,
          },
        ),
      },
    );
    final first = tester.getCenter(find.text('甲')).dy;
    final second = tester.getCenter(find.text('丙')).dy;
    final third = tester.getCenter(find.text('戊')).dy;
    expect(second, greaterThan(first));
    expect(third - second, greaterThan(second - first));
    expect(tester.takeException(), isNull);
  });

  testWidgets('四类内容标题放在导航栏，卡片只展示内容且没有审核状态', (tester) async {
    for (final section in TextbookContentSection.values) {
      await pump(tester, section);
      expect(
        find.widgetWithText(AppBar, '${section.label}·星月测试'),
        findsOneWidget,
      );
      expect(find.text('星月测试'), findsNothing);
      expect(find.text('待审核'), findsNothing);
      expect(find.byTooltip('编辑'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('保存审核'), findsNothing);
      switch (section) {
        case TextbookContentSection.reading:
          expect(
            tester
                .widget<TextbookCourseParagraphsContent>(
                  find.byType(TextbookCourseParagraphsContent),
                )
                .paragraphs
                .single
                .id,
            'paragraph-001',
          );
          expect(find.text('xīng'), findsNothing);
          expect(find.text('hē'), findsNothing);
          expect(find.text('yuè'), findsNothing);
          final plainRect = tester.getRect(
            find.byKey(const ValueKey('course-text-paragraph-001')),
          );
          await tester.tap(find.byTooltip('显示拼音'));
          await tester.pumpAndSettle();
          expect(find.text('xīng'), findsOneWidget);
          expect(find.text('hē'), findsOneWidget);
          expect(find.text('yuè'), findsOneWidget);
          expect(
            tester
                .getRect(
                  find.byKey(const ValueKey('course-text-paragraph-001')),
                )
                .height,
            greaterThan(plainRect.height),
          );
          await tester.tap(find.byTooltip('隐藏拼音'));
          await tester.pumpAndSettle();
          expect(find.text('xīng'), findsNothing);
          expect(find.text('hē'), findsNothing);
          expect(find.text('yuè'), findsNothing);
          for (final character in ['星', '𠀀', '，', '月', '。']) {
            expect(find.text(character), findsOneWidget);
          }
          expect(
            tester.getRect(
              find.byKey(const ValueKey('course-text-paragraph-001')),
            ),
            plainRect,
          );
        case TextbookContentSection.recognition:
          expect(
            find.byKey(const ValueKey('recognition-card-recognition-001')),
            findsOneWidget,
          );
          expect(find.text('hē'), findsOneWidget);
          final note = tester.widget<Text>(
            find.descendant(
              of: find.byKey(
                const ValueKey('recognition-note-recognition-001'),
              ),
              matching: find.byType(Text),
            ),
          );
          expect(
            note.textSpan!.toPlainText(includePlaceholders: false),
            '星𠀀，月。',
          );
          expect(find.text('课文词句：星𠀀，月'), findsNothing);
          expect(
            tester
                .widget<ColoredCard>(
                  find.byKey(
                    const ValueKey('recognition-card-recognition-001'),
                  ),
                )
                .onTap,
            isNull,
          );
          expect(find.byType(ColoredCard), findsOneWidget);
          expect(find.text('开始学习'), findsNothing);
          expect(find.text('继续学习'), findsNothing);
          expect(
            find.ancestor(
              of: find.byKey(
                const ValueKey('recognition-practice-recognition-001'),
              ),
              matching: find.byKey(
                const ValueKey('recognition-card-recognition-001'),
              ),
            ),
            findsOneWidget,
          );
          expect(find.text('家长核对生字'), findsNothing);
          expect(find.text('家长抽查'), findsNothing);
          expect(find.text('我来认'), findsNothing);
        case TextbookContentSection.writing:
          expect(
            tester
                .widget<TextbookWritingOverview>(
                  find.byType(TextbookWritingOverview),
                )
                .lesson
                .writingCharacters
                .single
                .id,
            'writing-001',
          );
          expect(
            find.byKey(const ValueKey('writing-card-writing-001')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('writing-practice-writing-001')),
            findsOneWidget,
          );
          // 卡面只显示字本身，拼音不进可见文案。
          expect(find.text('星'), findsOneWidget);
          expect(find.text('xīng'), findsNothing);
        case TextbookContentSection.recitation:
          expect(find.text('只背测试句的前两个字。'), findsOneWidget);
          expect(find.text('　　星𠀀'), findsOneWidget);
          expect(find.text('　　星𠀀，月。'), findsNothing);
        case TextbookContentSection.exercise:
          break;
      }
      if (section != TextbookContentSection.reading) {
        expect(find.byTooltip('显示拼音'), findsNothing);
        expect(find.byTooltip('隐藏拼音'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('不展示已通过状态；没有要求与尚未整理使用不同提示', (tester) async {
    await pump(
      tester,
      TextbookContentSection.reading,
      raw: courseFixture(reviewed: true),
    );
    expect(find.text('已通过'), findsNothing);
    expect(find.widgetWithText(AppBar, '读一读·星月测试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    for (final state in ['pending', 'notApplicable']) {
      final raw = courseFixture();
      final lesson = (raw['lessons'] as List).single as Map;
      lesson['recitations'] = <Object?>[];
      (lesson['coverage'] as Map)['recitations'] = state;
      await pump(tester, TextbookContentSection.recitation, raw: raw);
      expect(
        find.text(state == 'pending' ? '本课尚未整理背诵范围。' : '原书未要求本课背诵。'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('封面没有课目，窄屏和横屏大字的内容完整显示且可滚动', (tester) async {
    await pump(tester, TextbookContentSection.reading, pages: const [1]);
    expect(find.text('当前页暂无对应课目'), findsOneWidget);
    expect(find.text('请翻到课文页后再查看。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    for (final size in [const Size(320, 640), const Size(800, 280)]) {
      for (final section in TextbookContentSection.values) {
        await pump(tester, section, size: size, scale: 2);
        expect(
          find.widgetWithText(AppBar, '${section.label}·星月测试'),
          findsOneWidget,
        );
        final card = tester.getRect(
          find.byKey(const ValueKey('textbook-content-lesson-001')),
        );
        expect(card.left, 16);
        expect(card.right, size.width - 16);
        expect(tester.takeException(), isNull);
        if (section == TextbookContentSection.reading) {
          await tester.tap(find.byTooltip('显示拼音'));
          await tester.pumpAndSettle();
          expect(find.text('xīng'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('内容加载失败可重试，不把读取失败当作无内容', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookCourseProvider(book.pdfSha256).overrideWith((_) async {
            if (attempts++ == 0) throw StateError('read failed');
            return TextbookCoursePack.fromJson(courseFixture());
          }),
        ],
        child: MaterialApp(
          home: TextbookLessonContentPage(
            bookId: book.pdfSha256,
            section: TextbookContentSection.reading,
            pages: const [2],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('课文内容加载失败，请重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '读一读·星月测试'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('单题审核通过即可从教材详情进入做题页（字号=$scale）', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var creates = 0;
      var disposes = 0;
      final books = _Books();
      TextbookViewerOptions? current;
      final router = createAppRouter(
        initialLocation: AppRoutes.textbookDetailOf(book.pdfSha256),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            textbookListProvider.overrideWithValue([book]),
            textbookRepositoryProvider.overrideWithValue(books),
            textbookCatalogProvider.overrideWith((_) async => []),
            textbookFileServiceProvider.overrideWithValue(_Files()),
            textbookReadingContentProvider.overrideWith((_, __) async => null),
            textbookCourseProvider(book.pdfSha256).overrideWith(
              (_) async => TextbookCoursePack.fromJson(
                courseFixtureWithReviewedExercise(),
              ),
            ),
            textbookExerciseProgressProvider(book.pdfSha256)
                .overrideWith((_) async => null),
            textbookPreviewBuilderProvider.overrideWithValue((_, options) {
              current = options;
              return _Preview(
                options: options,
                onCreate: () => creates++,
                onDispose: () => disposes++,
              );
            }),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      current!.onPageChanged(2);
      await tester.pumpAndSettle();
      final entry = find.widgetWithText(TextButton, '练一练');
      expect(entry, findsOneWidget);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '练一练·星月测试'), findsOneWidget);
      final overview = tester.widget<TextbookExerciseOverview>(
        find.byType(TextbookExerciseOverview),
      );
      expect(overview.exercises.map((exercise) => exercise.id), [
        'exercise-001',
      ]);
      expect(find.text('完成'), findsOneWidget);
      expect(find.byType(ColoredCard), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(TextbookExerciseOverview),
          matching: find.byType(ColoredCard),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '完成'))
            .onPressed,
        isNotNull,
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(TextbookDetailPage), findsOneWidget);
      expect(find.text('第 2 页'), findsOneWidget);
      expect(creates, 1);
      expect(disposes, 0);
      expect(books.saved, [2]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('详情四入口随翻页变化，真实路由返回保留页码和 PDF 实例', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var creates = 0;
    var disposes = 0;
    final books = _Books();
    TextbookViewerOptions? current;
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookDetailOf(book.pdfSha256),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookListProvider.overrideWithValue([book]),
          textbookRepositoryProvider.overrideWithValue(books),
          textbookCatalogProvider.overrideWith((_) async => []),
          textbookFileServiceProvider.overrideWithValue(_Files()),
          textbookReadingContentProvider.overrideWith((_, __) async => null),
          textbookCourseProvider(book.pdfSha256).overrideWith(
            (_) async => TextbookCoursePack.fromJson(courseFixture()),
          ),
          textbookPreviewBuilderProvider.overrideWithValue((_, options) {
            current = options;
            return _Preview(
              options: options,
              onCreate: () => creates++,
              onDispose: () => disposes++,
            );
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前页暂无对应课目'), findsNothing);
    for (final section in TextbookContentSection.values) {
      if (section == TextbookContentSection.exercise) continue;
      expect(find.widgetWithText(TextButton, section.label), findsNothing);
    }
    current!.onPageChanged(2);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '练一练'), findsNothing);
    void expectCompactActionsBelowPdf() {
      final pdf = tester.getRect(
        find.byKey(const ValueKey('textbook-detail-preview-card')),
      );
      final controls = tester.getRect(
        find.byKey(const ValueKey('textbook-detail-controls')),
      );
      final buttons = [
        for (final section in TextbookContentSection.values)
          if (section != TextbookContentSection.exercise)
            tester.getRect(find.widgetWithText(TextButton, section.label)),
      ];
      expect(buttons.first.top, closeTo(pdf.bottom + SpacingTokens.md, 0.01));
      expect(buttons.last.bottom, lessThan(controls.top));
      expect(
        (buttons.first.left + buttons.last.right) / 2,
        closeTo(pdf.center.dx, 0.01),
      );
      for (var index = 1; index < buttons.length; index++) {
        expect(
          buttons[index].left - buttons[index - 1].right,
          closeTo(SpacingTokens.xs, 0.01),
        );
      }
    }

    expectCompactActionsBelowPdf();
    for (final section in TextbookContentSection.values) {
      if (section == TextbookContentSection.exercise) continue;
      await tester.tap(find.widgetWithText(TextButton, section.label));
      await tester.pumpAndSettle();
      expect(find.byType(TextbookLessonContentPage), findsOneWidget);
      expect(
        find.widgetWithText(AppBar, '${section.label}·星月测试'),
        findsOneWidget,
      );
      expect(creates, 1);
      expect(disposes, 0);
      if (section == TextbookContentSection.reading) {
        expect(find.text('xīng'), findsNothing);
        await tester.tap(find.byTooltip('显示拼音'));
        await tester.pumpAndSettle();
        expect(find.text('xīng'), findsOneWidget);
      }
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(TextbookDetailPage), findsOneWidget);
      expect(find.text('第 2 页'), findsOneWidget);
      expect(creates, 1);
      expect(disposes, 0);
    }
    await tester.tap(find.widgetWithText(TextButton, '读一读'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('显示拼音'), findsOneWidget);
    expect(find.text('xīng'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 280);
    await tester.pumpAndSettle();
    expectCompactActionsBelowPdf();
    await tester.tap(find.widgetWithText(TextButton, '认一认'));
    await tester.pumpAndSettle();
    final content = tester.widget<TextbookLessonContentPage>(
      find.byType(TextbookLessonContentPage),
    );
    expect(content.pages, [2, 3]);
    expect(books.saved, [2]);
    expect(tester.takeException(), isNull);
  });
}
