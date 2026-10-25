import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_course_editor_page.dart';
import 'package:poemath/features/textbook/textbook_course_node_page.dart';
import 'package:poemath/features/textbook/textbook_course_review_page.dart';
import 'package:poemath/features/textbook/textbook_draft_details_page.dart';
import 'package:poemath/features/textbook/textbook_source_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

import '../../helpers/textbook_course_fixture.dart';

class _Courses extends TextbookCourseRepository {
  TextbookCoursePack? current;
  bool failNextSave = false;
  int saves = 0;
  int imports = 0;
  @override
  Future<TextbookCoursePack?> load(Textbook book) async => current;
  @override
  Future<TextbookCoursePack> readDraft(Textbook book, String path) async =>
      TextbookCoursePack.fromJson(courseFixture());
  @override
  Future<void> importDraft(Textbook book, TextbookCoursePack pack) async {
    imports++;
    current = pack;
  }

  @override
  Future<void> save(
    Textbook book,
    TextbookCoursePack pack, {
    required TextbookCoursePack previous,
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('disk unavailable');
    }
    expect(current!.toJson(), previous.toJson());
    current = pack;
    saves++;
  }
}

class _Files extends TextbookFileService {
  @override
  Future<void> discardPickerCopy(String sourcePath) async {}
}

void main() {
  final book = courseFixtureBook();
  late _Courses courses;
  setUp(() {
    courses = _Courses()
      ..current = TextbookCoursePack.fromJson(courseFixture());
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool large = false,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookListProvider.overrideWithValue([book]),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
          textbookFileServiceProvider.overrideWithValue(_Files()),
        ],
        child: MaterialApp(
          builder: large
              ? (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  )
              : null,
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget launcher(Widget page) => Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context)
                .push<Object?>(MaterialPageRoute(builder: (_) => page)),
            child: const Text('打开审核'),
          ),
        ),
      );

  // 导入确认框下保留忙碌指示器，此时只推进有限帧，不等待无限动画。
  Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> fillReview(WidgetTester tester) async {
    for (final text in ['已对照原书页码和来源', '已逐项核对内容', '已逐字核对注音和多音字读音']) {
      await tap(tester, find.text(text));
    }
    final reviewer = find.widgetWithText(TextField, '审核人');
    await tester.ensureVisible(reviewer);
    await tester.enterText(reviewer, '核对家长');
    final notes = find.widgetWithText(TextField, '核对说明 / 退回原因');
    await tester.ensureVisible(notes);
    await tester.enterText(notes, '已与原书逐字核对');
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> twoWordsFixture() {
    final data = courseFixture(reviewed: true);
    final lesson = (data['lessons'] as List).single as Map<String, dynamic>;
    (lesson['words'] as List).add({
      ...courseFixtureText('word-002', '明月', ['míng', 'yuè']),
      'requirement': 'dictation',
    });
    return data;
  }

  testWidgets('三类字词各用一个两行省略的空格摘要，详情自动换行展示全部', (tester) async {
    final data = courseFixture();
    final lesson = (data['lessons'] as List).single as Map<String, dynamic>;
    final characters = List.filled(2, '春夏秋冬风雨雪山水花草星月天地日云林田园')
        .join()
        .runes
        .map(String.fromCharCode)
        .toList();
    const requirements = {
      'recognitionCharacters': 'recognition',
      'writingCharacters': 'writing',
      'words': 'reading',
    };
    for (final entry in requirements.entries) {
      lesson[entry.key] = [
        for (final (index, character) in characters.indexed)
          {
            ...courseFixtureText(
              '${entry.value}-$index',
              entry.key == 'words' ? '$character月' : character,
              null,
            ),
            'requirement': entry.value,
          },
      ];
    }
    courses.current = TextbookCoursePack.fromJson(data);
    await pump(tester, TextbookCourseReviewPage(bookId: book.pdfSha256));
    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));

    for (final category in requirements.keys) {
      final row = find.byKey(ValueKey('course-target-$category'));
      await tester.scrollUntilVisible(row, 250);
      await tester.pumpAndSettle();
      final tile = tester.widget<AppTile>(row);
      final texts = characters
          .map((character) => category == 'words' ? '$character月' : character)
          .toList();
      expect(tile.title, isEmpty);
      expect(tile.subtitle, texts.join(' '));
      expect(
        find.byKey(ValueKey('course-target-${requirements[category]}-0')),
        findsNothing,
      );
      final summary =
          find.descendant(of: row, matching: find.text(tile.subtitle));
      expect(tester.widget<Text>(summary).maxLines, 2);
      expect(tester.widget<Text>(summary).overflow, TextOverflow.ellipsis);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.descendant(of: summary, matching: find.byType(RichText)),
            )
            .didExceedMaxLines,
        isTrue,
      );
      await tap(tester, row);
      expect(
        find.text('${textbookCourseCategoryLabels[category]} · 待审核'),
        findsOneWidget,
      );
      final content = find.byType(TextbookCourseVocabularyContent);
      final terms = find.descendant(
        of: content,
        matching: find.byType(TextbookCourseText),
      );
      expect(
        tester
            .widgetList<TextbookCourseText>(terms)
            .map((term) => term.node.text),
        texts,
      );
      final first = tester.getRect(terms.first);
      final second = tester.getRect(terms.at(1));
      expect(second.top, closeTo(first.top, 0.1), reason: category);
      expect(second.left, greaterThan(first.right));
      expect(tester.getRect(terms.last).top, greaterThan(first.top));
      final body =
          tester.getRect(find.byKey(const ValueKey('course-content-body')));
      final rows = <double, List<Rect>>{};
      for (var index = 0; index < texts.length; index++) {
        final rect = tester.getRect(terms.at(index));
        expect(rect.left, greaterThanOrEqualTo(body.left));
        expect(rect.right, lessThanOrEqualTo(body.right + 0.1));
        rows.putIfAbsent(rect.top, () => []).add(rect);
      }
      for (final row in rows.values) {
        expect(
          (row.first.left + row.last.right) / 2,
          closeTo(body.center.dx, 0.1),
          reason: '$category 每行内容应水平居中',
        );
      }
      expect(find.textContaining('原书要求：'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(courses.saves, 0);
    expect(
      courses.current!.toJson(),
      TextbookCoursePack.fromJson(data).toJson(),
    );
  });

  testWidgets('窄屏两倍字号的长词按字换行，完整显示注音且不重叠', (tester) async {
    final data = twoWordsFixture();
    final lesson = (data['lessons'] as List).single as Map<String, dynamic>;
    (lesson['words'] as List).add({
      ...courseFixtureText('word-long', '春风秋霜山川日月星光', null),
      'requirement': 'reading',
    });
    courses.current = TextbookCoursePack.fromJson(data);
    await pump(
      tester,
      TextbookCourseNodePage(
        book: book,
        pack: courses.current!,
        nodeId: 'word-001',
        vocabularyCategory: 'words',
      ),
      size: const Size(320, 800),
      large: true,
    );
    final longWord = find.byKey(const ValueKey('course-text-word-long'));
    final characters = find
        .descendant(of: longWord, matching: find.byType(Text))
        .evaluate()
        .map((element) => element.widget as Text)
        .where((text) => text.data?.runes.length == 1)
        .toList();
    expect(characters.map((text) => text.data).join(), '春风秋霜山川日月星光');
    expect(
      tester.getRect(find.byWidget(characters.last)).top,
      greaterThan(tester.getRect(find.byWidget(characters.first)).top),
    );
    final body =
        tester.getRect(find.byKey(const ValueKey('course-content-body')));
    final pinyin =
        find.descendant(of: longWord, matching: find.byType(OverflowBox));
    final rects = [
      for (final token in tester.widgetList<Text>(
        find.descendant(of: pinyin, matching: find.byType(Text)),
      ))
        tester.getRect(find.byWidget(token)),
    ];
    expect(rects.length, characters.length);
    for (var i = 0; i < rects.length; i++) {
      expect(rects[i].left, greaterThanOrEqualTo(body.left));
      expect(rects[i].right, lessThanOrEqualTo(body.right + 0.1));
      if (i > 0 && (rects[i].top - rects[i - 1].top).abs() < 0.1) {
        expect(
          rects[i].left - rects[i - 1].right,
          greaterThanOrEqualTo(SpacingTokens.xs - 0.1),
        );
      }
    }
    expect(tester.takeException(), isNull);
    expect(courses.saves, 0);
  });

  testWidgets('字词分组审核失败不写入，重试一次保存全部独立审核', (tester) async {
    courses.current = TextbookCoursePack.fromJson(twoWordsFixture());
    final before = courses.current!.toJson();
    await pump(
      tester,
      launcher(
        TextbookCourseNodePage(
          book: book,
          pack: courses.current!,
          nodeId: 'word-001',
          vocabularyCategory: 'words',
        ),
      ),
    );
    await tap(tester, find.text('打开审核'));
    await tap(tester, find.byKey(const ValueKey('course-review-select-all')));
    expect(find.text('已核对原书的认读、书写或听写要求'), findsOneWidget);
    final notes = find.widgetWithText(TextField, '核对说明 / 退回原因');
    await tester.ensureVisible(notes);
    await tester.enterText(notes, '两项均已核对');
    courses.failNextSave = true;
    await tap(tester, find.text('通过审核'));
    expect(courses.current!.toJson(), before);
    expect(courses.saves, 0);
    expect(find.text('两项均已核对'), findsOneWidget);
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((box) => box.value == true),
      isTrue,
    );
    await tap(tester, find.text('通过审核'));
    final words = courses.current!.lessons.single.words;
    expect(words.map((word) => word.id), ['word-001', 'word-002']);
    expect(words.map((word) => word.text), ['星月', '明月']);
    expect(words.every((word) => word.isApproved), isTrue);
    expect(words.map((word) => word.review.reviewer).toSet(), {'家长'});
    expect(words.map((word) => word.review.reviewedAt).toSet().length, 1);
    expect(words.map((word) => word.review.notes).toSet(), {'两项均已核对'});
    expect(courses.saves, 1);
  });

  testWidgets('字词分组编辑选择单项，保留其他审核并清空当前勾选', (tester) async {
    courses.current = TextbookCoursePack.fromJson(twoWordsFixture());
    final first = courses.current!.lessons.single.words.first.toJson();
    await pump(
      tester,
      TextbookCourseNodePage(
        book: book,
        pack: courses.current!,
        nodeId: 'word-001',
        vocabularyCategory: 'words',
      ),
    );
    await tap(tester, find.byKey(const ValueKey('course-review-select-all')));
    await tap(tester, find.byTooltip('编辑内容'));
    expect(find.text('选择要编辑的字词'), findsOneWidget);
    await tap(tester, find.widgetWithText(AppTile, '明月'));
    await tester.enterText(find.widgetWithText(TextField, '字词内容'), '秋月');
    await tester.enterText(find.widgetWithText(TextField, '逐字注音'), 'qiū yuè');
    await tap(tester, find.text('保存修改'));
    expect(courses.current!.lessons.single.words.first.toJson(), first);
    expect(courses.current!.lessons.single.words.last.text, '秋月');
    expect(courses.current!.lessons.single.words.last.isApproved, isFalse);
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((box) => box.value == false),
      isTrue,
    );
    expect(find.byType(TextbookCourseText), findsNWidgets(2));
    expect(find.text('秋'), findsOneWidget);
    expect(courses.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('字词分组删除选择单项且须确认，保留其余字词和正文引用', (tester) async {
    courses.current = TextbookCoursePack.fromJson(twoWordsFixture());
    final before = courses.current!;
    await pump(
      tester,
      launcher(
        TextbookCourseNodePage(
          book: book,
          pack: courses.current!,
          nodeId: 'word-001',
          vocabularyCategory: 'words',
        ),
      ),
    );
    await tap(tester, find.text('打开审核'));
    await tap(tester, find.byTooltip('删除此项内容'));
    expect(find.text('选择要删除的字词'), findsOneWidget);
    await tap(tester, find.widgetWithText(AppTile, '明月'));
    await tap(tester, find.text('取消'));
    expect(courses.saves, 0);
    expect(courses.current!.toJson(), before.toJson());
    await tap(tester, find.byTooltip('删除此项内容'));
    await tap(tester, find.widgetWithText(AppTile, '明月'));
    await tap(tester, find.text('确认删除'));
    final lesson = courses.current!.lessons.single;
    expect(
      lesson.words.single.toJson(),
      before.lessons.single.words.first.toJson(),
    );
    expect(lesson.coverage['words'], TextbookCoverage.pending);
    expect(
      lesson.recognitionCharacters.single.toJson(),
      before.lessons.single.recognitionCharacters.single.toJson(),
    );
    expect(
      lesson.recitations.single.toJson(),
      before.lessons.single.recitations.single.toJson(),
    );
    expect(courses.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空状态导入草稿须确认，取消不写盘，确认后显示课目', (tester) async {
    courses.current = null;
    await pump(
      tester,
      TextbookCourseReviewPage(
        bookId: book.pdfSha256,
        pickDraftPath: () async => '/draft.json',
      ),
    );
    expect(find.text('从原书整理课程草稿'), findsOneWidget);
    await tap(tester, find.byTooltip('更多'));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('导出草稿 JSON'), findsOneWidget);
    expect(find.text('重新整理原书'), findsOneWidget);
    await tap(tester, find.text('导入课程草稿'), settle: false);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('导入课程草稿？'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(courses.imports, 0);
    await tap(tester, find.byTooltip('更多'));
    await tap(tester, find.text('导入课程草稿'), settle: false);
    await tap(tester, find.text('导入草稿'));
    expect(courses.imports, 1);
    expect(
      find.byKey(const ValueKey('course-lesson-lesson-001')),
      findsOneWidget,
    );
    expect(find.text('版次与来源'), findsNothing);
    await tap(tester, find.byTooltip('更多'));
    await tap(tester, find.text('版次与来源'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TextbookCourseNodePage), findsOneWidget);
  });

  testWidgets('课目展示六类目标，段落可查看逐字注音与审核清单', (tester) async {
    await pump(
      tester,
      ProviderScope(
        overrides: [
          textbookPathProvider(book.pdfSha256)
              .overrideWith((ref) async => null),
        ],
        child: TextbookCourseReviewPage(bookId: book.pdfSha256),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));
    expect(find.text('课文与注音'), findsOneWidget);
    expect(find.text('课文与注音 · 1'), findsNothing);
    final recognitionTile = tester.widget<AppTile>(
      find.byKey(const ValueKey('course-target-recognitionCharacters')),
    );
    final writingTile = tester.widget<AppTile>(
      find.byKey(const ValueKey('course-target-writingCharacters')),
    );
    expect(recognitionTile.subtitle, '𠀀');
    expect(recognitionTile.trailingText, '待审核');
    expect(writingTile.subtitle, '星');
    expect(writingTile.trailingText, '待审核');
    for (final id in ['recognitionCharacters', 'writingCharacters', 'words']) {
      await tap(tester, find.byKey(ValueKey('course-target-$id')));
      expect(find.byType(TextbookCourseText), findsOneWidget);
      expect(find.textContaining('原书要求：'), findsNothing);
      expect(
        tester.getRect(find.byType(TextbookCourseText)).center.dx,
        closeTo(
          tester
              .getRect(find.byKey(const ValueKey('course-content-body')))
              .center
              .dx,
          0.1,
        ),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('course-target-paragraphs')),
      -300,
    );
    await tap(
      tester,
      find.byKey(const ValueKey('course-target-paragraphs')),
    );
    expect(find.byType(TextbookCourseText), findsOneWidget);
    expect(find.text('𠀀'), findsOneWidget);
    expect(find.text('xīng'), findsOneWidget);
    expect(find.text('课文与注音 · 待审核'), findsOneWidget);
    expect(find.text('待审核'), findsNothing);
    expect(find.text('星月测试'), findsOneWidget);
    expect(find.text('原书依据'), findsNothing);
    expect(find.text('通过前需要处理'), findsNothing);
    expect(find.textContaining('字词尚未提供注音'), findsNothing);
    final content = find.byType(TextbookCourseParagraphsContent);
    final title = find.text('星月测试');
    final contentCard =
        find.ancestor(of: content, matching: find.byType(ColoredCard)).first;
    expect(
      tester.getRect(title).center.dx,
      closeTo(tester.getRect(contentCard).center.dx, 0.1),
    );
    expect(tester.widget<Text>(title).textAlign, TextAlign.center);
    final contentTheme = Theme.of(tester.element(content));
    expect(
      tester.widget<Text>(find.text('𠀀')).style!.fontSize,
      contentTheme.textTheme.titleSmall!.fontSize,
    );
    final sourceButton = find.byKey(const ValueKey('course-source-button'));
    final contentBody = find.byKey(const ValueKey('course-content-body'));
    expect(
      tester.getRect(sourceButton).center.dy,
      closeTo(tester.getRect(title).center.dy, 0.1),
    );
    expect(
      tester.getRect(contentCard).right - tester.getRect(sourceButton).right,
      closeTo(SpacingTokens.xs, 0.1),
    );
    final sourceArrowRect = tester.getRect(
      find.descendant(
        of: sourceButton,
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    expect(sourceArrowRect.size, const Size.square(SpacingTokens.lg));
    expect(
      tester.getRect(contentCard).right - sourceArrowRect.right,
      closeTo(SpacingTokens.xs, 0.1),
    );
    expect(
      tester.getRect(contentCard).bottom - tester.getRect(contentBody).bottom,
      closeTo(SpacingTokens.md, 0.1),
    );
    expect(
      find.descendant(
        of: find.byType(TextbookCourseText),
        matching: find.byType(Wrap),
      ),
      findsNothing,
    );
    expect(
      find.byType(PopupMenuButton<String>),
      findsNothing,
    );
    final reviewer = tester.widget<TextField>(
      find.widgetWithText(TextField, '审核人'),
    );
    expect(reviewer.decoration?.alignLabelWithHint, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '通过审核'))
          .onPressed,
      isNull,
    );
    expect(find.byTooltip('编辑内容'), findsOneWidget);
    await tap(tester, find.byTooltip('删除此项内容'));
    expect(find.text('删除此项内容？'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(courses.current!.toJson(), courseFixture());
    await tap(tester, find.text('原书'));
    final source = tester.widget<TextbookCourseSourcePage>(
      find.byType(TextbookCourseSourcePage),
    );
    expect(source.sources.single.pdfPage, 2);
    expect(courses.current!.toJson(), courseFixture());
  });

  testWidgets('范围弹窗从标题原书入口对照起始页，返回后保留未保存输入', (tester) async {
    final document = TextbookCourseDocument(
      courses.current!,
      const TextbookDraftManifest(
        runId: 'range-preview',
        parserVersion: 1,
        phase: 'ready',
        plans: [
          TextbookDraftPlan(
            id: 'lesson-001',
            startPage: 2,
            endPage: 3,
            title: '星月测试',
          ),
        ],
        completed: ['lesson-001'],
        candidates: {
          'lesson-001': [
            TextbookDraftCandidate(
              id: 'candidate-1',
              text: '待整理的文字',
              reason: '需要人工核对',
              pages: [2],
            ),
          ],
        },
      ),
    );
    await pump(
      tester,
      ProviderScope(
        overrides: [
          textbookCourseDocumentProvider(book.pdfSha256)
              .overrideWith((ref) async => document),
          textbookPathProvider(book.pdfSha256)
              .overrideWith((ref) async => null),
        ],
        child: TextbookDraftDetailsPage(book: book, lessonId: 'lesson-001'),
      ),
    );
    await tap(tester, find.widgetWithText(AppTile, 'PDF 第2–3页'));
    final anchor = find.widgetWithText(TextField, '正文标题锚点');
    await tester.enterText(anchor, '尚未保存的标题');
    await tap(tester, find.text('原书页'));
    final source = tester.widget<TextbookCourseSourcePage>(
      find.byType(TextbookCourseSourcePage),
    );
    expect(source.sources.single.pdfPage, 2);
    expect(courses.saves, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.widget<TextField>(anchor).controller!.text,
      '尚未保存的标题',
    );
    await tap(tester, find.text('取消'));
    expect(courses.saves, 0);
    expect(courses.current!.toJson(), courseFixture());
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏正文卡片使用安全区内的完整宽度', (tester) async {
    const size = Size(1100, 620);
    const insets = EdgeInsets.only(left: 24, right: 12);
    await pump(
      tester,
      MediaQuery(
        data: const MediaQueryData(size: size, padding: insets),
        child: TextbookCourseNodePage(
          book: book,
          pack: courses.current!,
          nodeId: 'paragraph-001',
        ),
      ),
      size: size,
    );
    final card = find.ancestor(
      of: find.byType(TextbookCourseText),
      matching: find.byType(ColoredCard),
    );
    final rect = tester.getRect(card);
    expect(rect.left, closeTo(insets.left + SpacingTokens.md, 0.1));
    expect(
      rect.right,
      closeTo(size.width - insets.right - SpacingTokens.md, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏课目子页铺满安全区，范围核对从导航栏进入', (tester) async {
    const size = Size(1100, 620);
    const insets = EdgeInsets.only(left: 24, right: 12);
    final data = courseFixture();
    final lesson =
        (data['lessons'] as List<dynamic>).single as Map<String, dynamic>;
    final paragraph =
        (lesson['paragraphs'] as List<dynamic>).single as Map<String, dynamic>;
    paragraph
      ..['text'] = '${paragraph['text']}\n${List.filled(40, '春风吹过星月。').join()}'
      ..['pinyin'] = null;
    final exercise =
        (lesson['exercises'] as List<dynamic>).single as Map<String, dynamic>;
    final prompt = List.generate(12, (index) => '问题${index + 1}：请读课文并说一说星月的特点。')
        .join('\n');
    exercise['prompt'] = prompt;
    courses.current = TextbookCoursePack.fromJson(data);
    tester.view.padding = const FakeViewPadding(left: 24, right: 12);
    addTearDown(tester.view.resetPadding);
    await pump(
      tester,
      TextbookCourseReviewPage(bookId: book.pdfSha256),
      size: size,
    );
    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));
    expect(find.text('课目信息与审核'), findsNothing);
    expect(find.text('核对内容范围'), findsNothing);
    final coverageButton = find.byTooltip('核对内容范围');
    expect(
      find.descendant(of: find.byType(AppBar), matching: coverageButton),
      findsOneWidget,
    );
    final buttonRect = tester.getRect(coverageButton);
    expect(buttonRect.center.dx, greaterThan(size.width / 2));
    expect(buttonRect.width, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
    expect(buttonRect.height, greaterThanOrEqualTo(SpacingTokens.minTapTarget));

    void expectFullWidth(Finder finder) {
      final rect = tester.getRect(finder);
      expect(rect.left, closeTo(insets.left + SpacingTokens.md, 0.1));
      expect(
        rect.right,
        closeTo(size.width - insets.right - SpacingTokens.md, 0.1),
      );
    }

    expectFullWidth(find.widgetWithText(AppTile, '原书范围与待整理内容'));
    final paragraphRow = find.byKey(const ValueKey('course-target-paragraphs'));
    await tester.ensureVisible(paragraphRow);
    await tester.pumpAndSettle();
    final tile = tester.widget<AppTile>(paragraphRow);
    expect(tile.title, isEmpty);
    expect(tile.subtitle, isNot(contains('\n')));
    expect(find.text('课文内容'), findsNothing);
    final summary = find.descendant(
      of: paragraphRow,
      matching: find.text(tile.subtitle),
    );
    expect(tester.widget<Text>(summary).maxLines, 2);
    expect(tester.widget<Text>(summary).overflow, TextOverflow.ellipsis);
    final renderedSummary = tester.renderObject<RenderParagraph>(
      find.descendant(of: summary, matching: find.byType(RichText)),
    );
    expect(renderedSummary.didExceedMaxLines, isTrue);
    final status = find.descendant(
      of: paragraphRow,
      matching: find.text('待审核'),
    );
    expect(
      tester.getRect(summary).right,
      closeTo(tester.getRect(status).left - SpacingTokens.sm, 0.1),
    );
    expect(
      tester.getSize(summary).width,
      greaterThan(tester.getSize(paragraphRow).width * 0.75),
    );
    final exerciseRow =
        find.byKey(const ValueKey('course-target-exercise-001'));
    await tester.scrollUntilVisible(exerciseRow, 300);
    await tester.pumpAndSettle();
    final exerciseTile = tester.widget<AppTile>(exerciseRow);
    expect(exerciseTile.subtitle, startsWith('问题1：'));
    expect(exerciseTile.subtitle, isNot(contains('\n')));
    final exerciseSummary = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(
          of: exerciseRow,
          matching: find.text(exerciseTile.subtitle),
        ),
        matching: find.byType(RichText),
      ),
    );
    expect(exerciseSummary.didExceedMaxLines, isTrue);
    await tap(tester, exerciseRow);
    expect(find.text(prompt), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(paragraphRow, -300);
    await tap(tester, coverageButton);
    expectFullWidth(find.byKey(const ValueKey('coverage-paragraphs')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('course-target-paragraphs')));
    await tap(tester, find.byTooltip('编辑内容'));
    expectFullWidth(find.widgetWithText(TextField, '正文'));
    expect(tester.takeException(), isNull);
    expect(courses.current!.toJson(), data);
  });

  testWidgets('窄屏大字长状态会省略，摘要保留可用宽度且整行可点击', (tester) async {
    var taps = 0;
    final summary = List.filled(30, '春风吹过星月。').join();
    final status = List.filled(10, '修改后待复核').join();
    await pump(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: AppTile(
            flat: true,
            flatTrailingEdgeAligned: true,
            iconColor: Colors.blue,
            title: '',
            subtitle: summary,
            subtitleMaxLines: 2,
            trailingText: status,
            onTap: () => taps++,
          ),
        ),
      ),
      large: true,
      size: const Size(320, 800),
    );
    for (final text in [summary, status]) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(tester.getSize(find.text(text)).width, greaterThan(0));
    }
    expect(find.text(''), findsNothing);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text(summary));
    expect(taps, 1);
  });

  testWidgets('正文标点后的抽取空格不占字格，换行和英文空格保留', (tester) async {
    const sourceText = '甲， 乙；　丙！\n丁， 戊。\n己庚\nA, B。';
    final data = courseFixture();
    final lesson =
        (data['lessons'] as List<dynamic>).single as Map<String, dynamic>;
    final paragraph =
        (lesson['paragraphs'] as List<dynamic>).single as Map<String, dynamic>;
    paragraph
      ..['text'] = sourceText
      ..['pinyin'] = null;
    lesson['recitations'] = <Object?>[];
    (lesson['coverage'] as Map<String, dynamic>)['recitations'] =
        TextbookCoverage.notApplicable.name;
    final node =
        TextbookCoursePack.fromJson(data).lessons.single.paragraphs.single;
    await pump(tester, Scaffold(body: TextbookCourseText(node: node)));

    final style = Theme.of(tester.element(find.byType(TextbookCourseText)))
        .textTheme
        .titleSmall;
    Finder character(String value) => find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data == value && widget.style == style,
        );
    final cellWidth = tester.getRect(character('庚')).left -
        tester.getRect(character('己')).left;
    expect(
      tester.getRect(character('乙')).left - tester.getRect(character('甲')).left,
      closeTo(2 * cellWidth, 0.1),
    );
    expect(
      tester.getRect(character('丙')).left - tester.getRect(character('乙')).left,
      closeTo(2 * cellWidth, 0.1),
    );
    expect(
      tester.getRect(character('戊')).left - tester.getRect(character('丁')).left,
      closeTo(2 * cellWidth, 0.1),
    );
    expect(
      tester.getRect(character('B')).left - tester.getRect(character('A')).left,
      closeTo(3 * cellWidth, 0.1),
    );
    expect(
      tester.getRect(character('乙')).center.dx,
      closeTo(tester.getRect(find.text('yǐ')).center.dx, 0.1),
    );
    expect(find.byKey(const ValueKey('course-text-line-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('course-text-line-4')), findsNothing);
    expect(node.text, sourceText);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文缺少原书注音时生成可编辑的逐字拼音草稿', (tester) async {
    final data = courseFixture();
    final lesson =
        (data['lessons'] as List<dynamic>).single as Map<String, dynamic>;
    final paragraph =
        (lesson['paragraphs'] as List<dynamic>).single as Map<String, dynamic>;
    paragraph
      ..['text'] = '小青蛙。'
      ..['pinyin'] = null;
    lesson['recitations'] = <Object?>[];
    (lesson['coverage'] as Map<String, dynamic>)['recitations'] =
        TextbookCoverage.notApplicable.name;
    courses.current = TextbookCoursePack.fromJson(data);

    await pump(
      tester,
      TextbookCourseReviewPage(bookId: book.pdfSha256),
    );
    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));
    await tap(
      tester,
      find.byKey(const ValueKey('course-target-paragraphs')),
    );

    for (final value in ['xiǎo', 'qīng', 'wā', '小', '青', '蛙']) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('已逐字核对注音和多音字读音'), findsOneWidget);

    await tap(tester, find.byTooltip('编辑内容'));
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '逐字注音'))
          .controller!
          .text,
      'xiǎo qīng wā 。',
    );
  });

  testWidgets('多段课文只有一个入口，分段展示并一次审核全部段落', (tester) async {
    final data = courseFixture();
    final lesson =
        (data['lessons'] as List<dynamic>).single as Map<String, dynamic>;
    (lesson['paragraphs'] as List<dynamic>).add(
      courseFixtureText(
        'paragraph-002',
        '第二段。',
        ['dì', 'èr', 'duàn', '。'],
      ),
    );
    courses.current = TextbookCoursePack.fromJson(data);

    await pump(tester, TextbookCourseReviewPage(bookId: book.pdfSha256));
    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));
    expect(
      find.byKey(const ValueKey('course-target-paragraphs')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('course-target-paragraph-001')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('course-target-paragraph-002')),
      findsNothing,
    );

    await tap(tester, find.byKey(const ValueKey('course-target-paragraphs')));
    expect(find.byType(TextbookCourseText), findsNWidgets(2));
    expect(find.text('星月测试'), findsOneWidget);
    expect(
      tester
          .widgetList<TextbookCourseText>(find.byType(TextbookCourseText))
          .map((content) => content.node.text),
      ['星𠀀，月。', '第二段。'],
    );
    final paragraphContents = find.byType(TextbookCourseText);
    expect(
      tester.getRect(paragraphContents.at(1)).top -
          tester.getRect(paragraphContents.at(0)).bottom,
      closeTo(SpacingTokens.md, 0.1),
    );
    expect(
      tester.getRect(find.text('星')).left,
      closeTo(tester.getRect(find.text('第')).left, 0.1),
    );

    await fillReview(tester);
    await tap(tester, find.text('通过审核'));

    final paragraphs = courses.current!.lessons.single.paragraphs;
    expect(paragraphs.every((paragraph) => paragraph.isApproved), isTrue);
    expect(
      paragraphs.map((paragraph) => paragraph.review.reviewer).toSet(),
      {'核对家长'},
    );
    expect(
      paragraphs.map((paragraph) => paragraph.review.reviewedAt).toSet().length,
      1,
    );
  });

  testWidgets('课目隐藏待核对，审核状态统一放在右侧箭头前', (tester) async {
    final data = courseFixture();
    final lesson =
        (data['lessons'] as List<dynamic>).single as Map<String, dynamic>;
    lesson['coverage'] = {
      for (final category in TextbookCoursePack.categories)
        category: TextbookCoverage.pending.name,
    };
    courses.current = TextbookCoursePack.fromJson(data);

    await pump(
      tester,
      TextbookCourseReviewPage(bookId: book.pdfSha256),
      size: const Size(720, 1600),
    );
    final rootLesson = tester.widget<AppTile>(
      find.byKey(const ValueKey('course-lesson-lesson-001')),
    );
    expect(rootLesson.subtitle, isNot(contains('待审核')));
    expect(rootLesson.trailingText, '待审核');
    final rootUnitRow = find.byKey(const ValueKey('course-unit-unit-001'));
    final rootUnitArrowRect = tester.getRect(
      find.descendant(
        of: rootUnitRow,
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    expect(rootUnitArrowRect.size, const Size.square(SpacingTokens.lg));
    final referenceArrowRight = rootUnitArrowRect.right;
    final rootLessonRow =
        find.byKey(const ValueKey('course-lesson-lesson-001'));
    final rootLessonArrowRect = tester.getRect(
      find.descendant(
        of: rootLessonRow,
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    final rootLessonStatusRect = tester.getRect(
      find.descendant(of: rootLessonRow, matching: find.text('待审核')),
    );
    expect(rootLessonArrowRect.right, closeTo(referenceArrowRight, 0.1));
    expect(rootLessonArrowRect.size, const Size.square(SpacingTokens.lg));
    expect(
      rootLessonArrowRect.left - rootLessonStatusRect.right,
      closeTo(SpacingTokens.xs, 0.1),
    );

    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));
    expect(find.text('待核对'), findsNothing);

    expect(find.byKey(const ValueKey('course-lesson-review')), findsNothing);

    for (final id in [
      'paragraphs',
      'recognitionCharacters',
      'writingCharacters',
      'words',
      'recitation-001',
      'exercise-001',
    ]) {
      final tile = tester.widget<AppTile>(
        find.byKey(ValueKey('course-target-$id')),
      );
      expect(tile.trailingText, '待审核');
      if (id == 'recitation-001' || id == 'exercise-001') {
        expect(tile.title, isEmpty);
        expect(tile.subtitle, isNotEmpty);
      }
      final row = find.byKey(ValueKey('course-target-$id'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final arrowRect = tester.getRect(
        find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
      );
      expect(arrowRect.right, closeTo(referenceArrowRight, 0.1));
      expect(arrowRect.size, const Size.square(SpacingTokens.lg));
    }

    await tap(tester, find.byTooltip('核对内容范围'));
    expect(find.text('待核对'), findsNothing);
    for (final category in TextbookCoursePack.categories) {
      final row = find.byKey(ValueKey('coverage-$category'));
      expect(tester.widget<AppTile>(row).trailingText, isNull);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final arrowRect = tester.getRect(
        find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
      );
      expect(arrowRect.right, closeTo(referenceArrowRight, 0.1));
      expect(arrowRect.size, const Size.square(SpacingTokens.lg));
    }
  });

  testWidgets('逐项核对紧贴文案，支持全选和部分选中，默认审核人为家长', (tester) async {
    await pump(
      tester,
      launcher(
        TextbookCourseNodePage(
          book: book,
          pack: courses.current!,
          nodeId: 'paragraph-001',
        ),
      ),
      size: const Size(720, 800),
    );
    await tap(tester, find.text('打开审核'));

    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(4));
    final firstRect = tester.getRect(checkboxes.at(1));
    final secondRect = tester.getRect(checkboxes.at(2));
    final thirdRect = tester.getRect(checkboxes.at(3));
    expect(secondRect.center.dy, closeTo(firstRect.center.dy, 0.1));
    expect(thirdRect.center.dy, closeTo(firstRect.center.dy, 0.1));

    final firstLabel = tester.getRect(find.text('已对照原书页码和来源'));
    expect(
      firstLabel.left - firstRect.right,
      lessThanOrEqualTo(SpacingTokens.sm),
    );
    final selectAll = find.byKey(const ValueKey('course-review-select-all'));
    final selectAllCheckbox = find.descendant(
      of: selectAll,
      matching: find.byType(Checkbox),
    );
    final headingRect = tester.getRect(find.text('逐项核对'));
    final selectAllRect = tester.getRect(selectAllCheckbox);
    expect(selectAllRect.left, greaterThan(headingRect.right));
    expect(selectAllRect.center.dy, closeTo(headingRect.center.dy, 0.1));
    expect(tester.widget<Checkbox>(selectAllCheckbox).value, isFalse);
    final reviewer = tester.widget<TextField>(
      find.widgetWithText(TextField, '审核人'),
    );
    expect(reviewer.controller!.text, '家长');
    await tap(tester, find.text('已对照原书页码和来源'));
    expect(tester.widget<Checkbox>(selectAllCheckbox).value, isNull);
    await tap(tester, selectAll);
    expect(
      tester.widgetList<Checkbox>(checkboxes).every((c) => c.value!),
      isTrue,
    );
    await tap(tester, selectAll);
    expect(
      tester.widgetList<Checkbox>(checkboxes).every((c) => c.value == false),
      isTrue,
    );
    await tap(tester, selectAll);
    final notes = find.widgetWithText(TextField, '核对说明 / 退回原因');
    await tester.ensureVisible(notes);
    await tester.enterText(notes, '已逐项核对');
    await tap(tester, find.text('通过审核'));
    final review = courses.current!.lessons.single.paragraphs.single.review;
    expect(review.reviewer, '家长');
    expect(review.checks, containsAll(['sourcePages', 'content', 'pinyin']));
  });

  for (final large in [false, true]) {
    testWidgets('正文首行缩进两格，拼音不重叠，长行可横向查看（大字=$large）', (tester) async {
      final data = courseFixture();
      final lesson =
          (data['lessons'] as List<dynamic>).single as Map<String, dynamic>;
      final paragraph = (lesson['paragraphs'] as List<dynamic>).single
          as Map<String, dynamic>;
      paragraph
        ..['text'] = '　　　霜风吹夏雨落秋霜降冬雪飘\n春水清。\n　保护禾苗。'
        ..['pinyin'] = null;
      lesson['recitations'] = <Object?>[];
      (lesson['coverage'] as Map<String, dynamic>)['recitations'] =
          TextbookCoverage.notApplicable.name;
      final node =
          TextbookCoursePack.fromJson(data).lessons.single.paragraphs.single;

      await pump(
        tester,
        Scaffold(
          body: SizedBox(
            width: 180,
            child: TextbookCourseText(node: node),
          ),
        ),
        size: const Size(220, 400),
        large: large,
      );

      expect(find.byKey(const ValueKey('course-text-line-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('course-text-line-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('course-text-line-2')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TextbookCourseText),
          matching: find.byType(Wrap),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(TextbookCourseText),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
      expect(
        tester.getRect(find.text('霜').first).center.dy,
        closeTo(tester.getRect(find.text('飘')).center.dy, 0.1),
      );
      expect(
        tester.getRect(find.text('霜').first).left,
        closeTo(
          tester.getRect(find.text('春')).left +
              2 *
                  (tester.getRect(find.text('水')).left -
                      tester.getRect(find.text('春')).left),
          0.1,
        ),
      );
      expect(
        tester.getRect(find.text('保')).left,
        greaterThan(tester.getRect(find.text('春')).left),
      );
      expect(
        tester.getRect(find.text('shuāng').first).left,
        lessThan(tester.getRect(find.text('霜').first).left),
      );
      final pinyinInFirstLine = find.descendant(
        of: find.byKey(const ValueKey('course-text-line-0')),
        matching: find.byType(OverflowBox),
      );
      final tokens = tester
          .widgetList<Text>(
            find.descendant(
              of: pinyinInFirstLine,
              matching: find.byType(Text),
            ),
          )
          .toList();
      for (var index = 1; index < tokens.length; index++) {
        final prior = tester.getRect(find.byWidget(tokens[index - 1]));
        final current = tester.getRect(find.byWidget(tokens[index]));
        expect(
          current.left - prior.right,
          greaterThanOrEqualTo(SpacingTokens.xs),
        );
      }

      final theme = Theme.of(tester.element(find.byType(TextbookCourseText)));
      expect(
        tester.widget<Text>(find.text('霜').first).style?.fontSize,
        theme.textTheme.titleSmall?.fontSize,
      );
      expect(
        tester.widget<Text>(find.text('春')).style?.fontSize,
        theme.textTheme.titleSmall?.fontSize,
      );
      expect(
        tester.widget<Text>(find.text('shuāng').first).style?.fontSize,
        theme.textTheme.bodySmall?.fontSize,
      );
      final viewport = find.byType(SingleChildScrollView);
      expect(
        tester.getRect(find.text('飘')).right,
        greaterThan(tester.getRect(viewport).right),
      );
      await tester.drag(viewport, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('飘')).right,
        lessThanOrEqualTo(tester.getRect(viewport).right),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('列表尚未刷新时打开课目使用持久层最新内容', (tester) async {
    await pump(tester, TextbookCourseReviewPage(bookId: book.pdfSha256));
    // Keep the old provider snapshot visible, as when generation just finishes.
    courses.current = editTextbookCourseNode(
      courses.current!,
      courses.current!.lessons.first.paragraphs.single.id,
      {'text': '星𠀀，月明。', 'pinyin': null},
    );
    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));
    expect(find.textContaining('星𠀀，月明。'), findsOneWidget);
    await tap(
      tester,
      find.byKey(const ValueKey('course-target-paragraphs')),
    );
    expect(find.text('尚未提供注音'), findsNothing);
    expect(find.text('通过前需要处理'), findsNothing);
    expect(find.textContaining('请先补充'), findsNothing);
    expect(find.text('míng'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TextbookCourseText),
        matching: find.byType(SelectableText),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑正文注音保存，相关审核失效，可重新逐项审核', (tester) async {
    courses.current =
        TextbookCoursePack.fromJson(courseFixture(reviewed: true));
    await pump(
      tester,
      launcher(
        TextbookCourseNodePage(
          book: book,
          pack: courses.current!,
          nodeId: 'paragraph-001',
        ),
      ),
    );
    await tap(tester, find.text('打开审核'));
    await tap(tester, find.byTooltip('编辑内容'));
    await tester.enterText(find.widgetWithText(TextField, '正文'), '月𠀀，星。');
    await tester.enterText(
      find.widgetWithText(TextField, '逐字注音'),
      'yuè hē ， xīng 。',
    );
    await tap(tester, find.text('保存修改'));
    expect(courses.current!.lessons.single.paragraphs.single.text, '月𠀀，星。');
    expect(
      courses.current!.lessons.single.recitations.single.isApproved,
      isFalse,
    );
    expect(find.byType(TextbookCourseEditorPage), findsNothing);
    await fillReview(tester);
    await tap(tester, find.text('通过审核'));
    expect(
      courses.current!.lessons.single.paragraphs.single.isApproved,
      isTrue,
    );
    expect(
      courses.current!.lessons.single.paragraphs.single.review.reviewer,
      '核对家长',
    );
    expect(courses.current!.status, 'draft');
  });

  testWidgets('审核写入失败保留输入并可重试，退回保存原因', (tester) async {
    await pump(
      tester,
      launcher(
        TextbookCourseNodePage(
          book: book,
          pack: courses.current!,
          nodeId: 'paragraph-001',
        ),
      ),
    );
    await tap(tester, find.text('打开审核'));
    await fillReview(tester);
    courses.failNextSave = true;
    await tap(tester, find.text('通过审核'));
    expect(find.text('审核保存失败，请重试；填写内容已保留'), findsOneWidget);
    expect(find.text('已与原书逐字核对'), findsOneWidget);
    expect(
      courses.current!.lessons.single.paragraphs.single.isApproved,
      isFalse,
    );
    await tap(tester, find.text('退回修改'));
    expect(
      courses.current!.lessons.single.paragraphs.single.review.status,
      TextbookReviewStatus.rejected,
    );
    expect(
      courses.current!.lessons.single.paragraphs.single.review.notes,
      '已与原书逐字核对',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('词语要求和来源可编辑，错位注音阻止保存并保留输入', (tester) async {
    await pump(
      tester,
      launcher(
        TextbookCourseEditorPage(
          book: book,
          pack: courses.current!,
          node: courses.current!.lessons.single.words.single,
        ),
      ),
    );
    await tap(tester, find.text('打开审核'));
    await tap(tester, find.text('阅读词语'));
    await tap(tester, find.text('听写词语').last);
    await tester.enterText(find.widgetWithText(TextField, '逐字注音'), 'chOn');
    await tap(tester, find.text('保存修改'));
    expect(find.byType(TextbookCourseEditorPage), findsOneWidget);
    expect(courses.current!.lessons.single.words.single.requirement, 'reading');
    await tester.enterText(find.widgetWithText(TextField, '逐字注音'), 'xīng yuè');
    final page = find.widgetWithText(TextField, '来源 1 · PDF 页码');
    await tester.ensureVisible(page);
    await tester.enterText(page, '3');
    await tap(tester, find.text('保存修改'));
    expect(
      courses.current!.lessons.single.words.single.requirement,
      'dictation',
    );
    expect(
      courses.current!.lessons.single.words.single.sources.single.pdfPage,
      3,
    );
  });

  testWidgets('窄屏大字可编辑背诵范围，按Unicode码点显示选文', (tester) async {
    await pump(
      tester,
      launcher(
        TextbookCourseEditorPage(
          book: book,
          pack: courses.current!,
          node: courses.current!.lessons.single.recitations.single,
        ),
      ),
      large: true,
    );
    await tap(tester, find.text('打开审核'));
    final first = find.widgetWithText(TextField, '起始字符');
    await tester.ensureVisible(first);
    await tester.enterText(first, '2');
    await tester.pumpAndSettle();
    expect(find.text('𠀀'), findsOneWidget);
    await tap(tester, find.text('保存修改'));
    expect(
      courses.current!.lessons.single.recitations.single.ranges.single.start,
      1,
    );
    expect(
      courses
          .current!.lessons.single.recitations.single.ranges.single.textSha256,
      textbookTextDigest('𠀀'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('对照原书从指定页打开，跳页不依赖或写入孩子阅读记录', (tester) async {
    final seen = <int>[];
    var reported = false;
    await pump(
      tester,
      ProviderScope(
        overrides: [
          textbookPathProvider(book.pdfSha256)
              .overrideWith((ref) async => '/sample.pdf'),
        ],
        child: TextbookCourseSourcePage(
          book: book,
          sources: const [TextbookSourcePage(2, '1', 'manual')],
          viewerBuilder: (context, options) {
            seen.add(options.initialPage);
            if (!reported) {
              reported = true;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => options.onPageChanged(3));
            }
            return const Text('原页查看器');
          },
        ),
      ),
    );
    expect(seen.first, 2);
    expect(find.text('第 3 / 3 页'), findsOneWidget);
    expect(courses.current!.toJson(), courseFixture());
    expect(tester.takeException(), isNull);
  });

  testWidgets('习题可补充参考答案，来源语义一起保存', (tester) async {
    await pump(
      tester,
      launcher(
        TextbookCourseEditorPage(
          book: book,
          pack: courses.current!,
          node: courses.current!.lessons.single.exercises.single,
        ),
      ),
    );
    await tap(tester, find.text('打开审核'));
    await tap(tester, find.text('家长核对'));
    await tap(tester, find.text('参考答案').last);
    await tap(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, '答案来源'),
    );
    await tap(tester, find.text('审核者参考要点').last);
    await tap(tester, find.text('添加答案'));
    final answer = find.widgetWithText(TextField, '答案 1');
    await tester.ensureVisible(answer);
    await tester.enterText(answer, '合理描述即可，不作为唯一答案');
    await tap(tester, find.text('保存修改'));
    final exercise = courses.current!.lessons.single.exercises.single;
    expect(exercise.answerType, TextbookAnswerType.reference);
    expect(exercise.answerOrigin, 'reviewerReference');
    expect(exercise.answers, ['合理描述即可，不作为唯一答案']);
  });

  testWidgets('在App核对各类覆盖状态，保存后课目审核失效', (tester) async {
    courses.current =
        TextbookCoursePack.fromJson(courseFixture(reviewed: true));
    await pump(tester, TextbookCourseReviewPage(bookId: book.pdfSha256));
    await tap(tester, find.byKey(const ValueKey('course-lesson-lesson-001')));
    await tap(tester, find.byTooltip('核对内容范围'));
    expect(
      find.byType(DropdownButtonFormField<TextbookCoverage>),
      findsNothing,
    );
    for (final category in TextbookCoursePack.categories) {
      final row = find.byKey(ValueKey('coverage-$category'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final titleRect = tester.getRect(
        find.descendant(
          of: row,
          matching: find.text(textbookCourseCategoryLabels[category]!),
        ),
      );
      final statusRect = tester.getRect(
        find.descendant(of: row, matching: find.text('已整理完整')),
      );
      final arrowRect = tester.getRect(
        find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
      );
      expect(statusRect.center.dy, closeTo(titleRect.center.dy, 0.1));
      expect(statusRect.center.dy, closeTo(arrowRect.center.dy, 0.1));
      expect(statusRect.left, greaterThanOrEqualTo(titleRect.right));
      expect(arrowRect.left, greaterThanOrEqualTo(statusRect.right));
      await tap(tester, row);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('原书无此要求'),
        ),
        findsNothing,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    }
    await tap(
      tester,
      find.byKey(const ValueKey('coverage-words')),
    );
    await tap(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('待核对'),
      ),
    );
    await tap(tester, find.text('保存范围核对'));
    expect(
      courses.current!.lessons.single.coverage['words'],
      TextbookCoverage.pending,
    );
    expect(courses.current!.lessons.single.isApproved, isFalse);
    expect(find.byTooltip('核对内容范围'), findsOneWidget);
  });
}
