import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_detail_page.dart';
import 'package:poemath/features/textbook/textbook_lesson_content_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

import '../../helpers/textbook_course_fixture.dart';

class _Files extends TextbookFileService {
  @override
  Future<String?> installedPath(Textbook book) async => '/sample.pdf';
}

class _Books implements TextbookRepository {
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
  Future<void> addIfAbsent(Textbook book) async {}
  @override
  Future<void> setMatch(
    String profileId,
    String id,
    TextbookMatch match,
  ) async {}
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.options.onReady(
        (page) async => widget.options.onPageChanged(page),
      ),
    );
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
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookCourseProvider(book.pdfSha256).overrideWith(
            (_) async => TextbookCoursePack.fromJson(raw ?? courseFixture()),
          ),
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
        case TextbookContentSection.recognition:
          expect(
            tester
                .widget<TextbookCourseVocabularyContent>(
                  find.byType(TextbookCourseVocabularyContent),
                )
                .vocabulary
                .single
                .id,
            'recognition-001',
          );
        case TextbookContentSection.writing:
          expect(
            tester
                .widget<TextbookCourseVocabularyContent>(
                  find.byType(TextbookCourseVocabularyContent),
                )
                .vocabulary
                .single
                .id,
            'writing-001',
          );
        case TextbookContentSection.recitation:
          expect(find.text('只背测试句的前两个字。'), findsOneWidget);
          expect(find.text('　　星𠀀'), findsOneWidget);
          expect(find.text('　　星𠀀，月。'), findsNothing);
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
    expect(find.text('当前页暂无对应课目，请翻到课文页后再查看。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    for (final size in [const Size(320, 640), const Size(800, 280)]) {
      for (final section in TextbookContentSection.values) {
        await pump(tester, section, size: size, scale: 2);
        expect(
          find.widgetWithText(AppBar, '${section.label}·星月测试'),
          findsOneWidget,
        );
        final card = tester
            .getRect(find.byKey(const ValueKey('textbook-content-lesson-001')));
        expect(card.left, 16);
        expect(card.right, size.width - 16);
        expect(tester.takeException(), isNull);
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
      expect(find.widgetWithText(TextButton, section.label), findsNothing);
    }
    current!.onPageChanged(2);
    await tester.pumpAndSettle();
    void expectCompactActionsBelowPdf() {
      final pdf = tester.getRect(
        find.byKey(const ValueKey('textbook-detail-preview-card')),
      );
      final controls = tester.getRect(
        find.byKey(const ValueKey('textbook-detail-controls')),
      );
      final buttons = [
        for (final section in TextbookContentSection.values)
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
      await tester.tap(find.widgetWithText(TextButton, section.label));
      await tester.pumpAndSettle();
      expect(find.byType(TextbookLessonContentPage), findsOneWidget);
      expect(
        find.widgetWithText(AppBar, '${section.label}·星月测试'),
        findsOneWidget,
      );
      expect(creates, 1);
      expect(disposes, 0);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(TextbookDetailPage), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(creates, 1);
      expect(disposes, 0);
    }
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
