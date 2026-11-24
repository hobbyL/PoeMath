import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/features/english/english_course_page.dart';
import 'package:poemath/features/english/english_history_page.dart';
import 'package:poemath/features/english/english_practice_page.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_study_page.dart';
import 'package:poemath/features/english/english_tab_page.dart';
import 'package:poemath/features/english/english_target_editor.dart';
import 'package:poemath/features/english/english_widgets.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/english_fixture.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

class _Courses extends EnglishCourseRepository {
  EnglishCourse course = englishCourse();
  @override
  Future<EnglishCourse?> load(Textbook book) async => course;
  @override
  Future<T> withCurrent<T>(
    Textbook book,
    Future<T> Function(EnglishCourse?) action,
  ) => action(course);
  @override
  Future<EnglishCourse> saveLesson(
    Textbook book,
    EnglishLesson lesson, {
    required int expectedRevision,
    required void Function() check,
    bool adopt = false,
  }) async {
    check();
    if (expectedRevision != course.revision) throw StateError('conflict');
    return course = course.change({
      'revision': course.revision + 1,
      'lessons': [
        for (final l in course.lessons)
          (l.id == lesson.id ? lesson : l).toJson(),
      ],
    });
  }
}

void main() {
  late _Courses courses;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    courses = _Courses();
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForWidgetTesting();
  });
  List<Override> overrides({Map<String, int> cardNumbers = const {}}) => [
    textbookListProvider.overrideWith((ref) => [englishBook()]),
    englishCourseRepositoryProvider.overrideWithValue(courses),
    englishTargetCardNumberProvider.overrideWith(
      (ref, key) async => cardNumbers,
    ),
    englishReviewPageImageBuilderProvider.overrideWithValue(
      (book, page) =>
          SizedBox(key: ValueKey('review-source-page-$page'), height: 120),
    ),
    englishVoicesProvider.overrideWith(
      (ref) async => [
        {'locale': 'en-US', 'name': 'test', 'network_required': 'false'},
      ],
    ),
  ];
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    AppSubject subject = AppSubject.poem,
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    double textScale = 1,
    Map<String, int> cardNumbers = const {},
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(cardNumbers: cardNumbers),
        child: MaterialApp(
          theme: AppTheme.resolve(subject: subject, brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  bool submitReady(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '提交答案'))
          .onPressed !=
      null;
  testWidgets('具体词句编辑保存后返回来源课时，其他课时内容不变', (tester) async {
    final book = englishBook();
    final sourceLesson = courses.course.lessons.single;
    final lesson = sourceLesson.change({
      'targets': [
        for (final target in sourceLesson.targets)
          (target.id == 'word-1' ? target.change({'role': 'Mother'}) : target)
              .toJson(),
      ],
    });
    courses.course = englishCourse(
      book: book,
      lessons: [
        lesson,
        englishLesson(
          id: 'unit-2-p2',
          unit: 'Unit 2 River',
          targets: [englishWord(id: 'river-word', text: 'green boat')],
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: AppRoutes.englishBookOf(
        book.pdfSha256,
        lesson: lesson.id,
        review: true,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.englishReviewLesson,
          builder: (_, s) => EnglishLessonPage(
            bookId: s.pathParameters['id']!,
            lessonId: s.pathParameters['lesson']!,
            review: true,
          ),
        ),
        GoRoute(
          path: AppRoutes.englishTargetEdit,
          builder: (_, s) => EnglishTargetEditor(
            bookId: s.pathParameters['id']!,
            lessonId: s.pathParameters['lesson']!,
            targetId: s.pathParameters['target']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(
          theme: AppTheme.resolve(
            subject: AppSubject.poem,
            brightness: Brightness.light,
          ),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('1. red kite'));
    await tester.tap(find.text('1. red kite'));
    await tester.pumpAndSettle();
    expect(find.text('编辑英语内容'), findsOneWidget);
    expect(find.text('green boat'), findsNothing);
    expect(find.text('Unit 1 Garden · Lesson 1'), findsNothing);
    expect(find.text('原书来源'), findsNothing);
    expect(find.text('打开原书核对'), findsNothing);
    expect(find.text('来源裁切区域'), findsNothing);
    expect(find.text('顺序与审核'), findsNothing);
    expect(find.text('英语声音'), findsNothing);
    expect(find.text('说话角色（可选）'), findsNothing);
    expect(find.textContaining('完成试听后'), findsNothing);
    expect(find.text('将这块区域作为学习图片'), findsNothing);
    final approvalHint = find.text('保存后向孩子开放，未勾选则保存为草稿。');
    final approvalHintStyle = tester.widget<Text>(approvalHint).style;
    final bodyStyle = Theme.of(tester.element(approvalHint))
        .textTheme
        .bodyMedium;
    expect(approvalHintStyle?.fontSize, lessThan(bodyStyle!.fontSize!));
    final contentTypeSelector = find.byKey(
      const ValueKey('english-content-type-selector'),
    );
    expect(
      find.descendant(
        of: contentTypeSelector,
        matching: find.byType(InputDecorator),
      ),
      findsOneWidget,
    );
    final audition = find.text('试听当前声音');
    final save = find.text('保存并返回课时');
    expect(audition, findsOneWidget);
    expect(save, findsOneWidget);
    expect(tester.getRect(audition).top, tester.getRect(save).top);
    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getRect(save).bottom,
      allOf(greaterThan(logicalHeight - 90), lessThanOrEqualTo(logicalHeight)),
    );
    await tester.tap(contentTypeSelector);
    await tester.pumpAndSettle();
    expect(find.text('选择内容类型'), findsOneWidget);
    await tester.tap(find.text('对话与故事'));
    await tester.pumpAndSettle();
    expect(find.text('对话与故事'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'silver kite');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      Uri.parse(
        AppRoutes.englishBookOf(
          book.pdfSha256,
          lesson: lesson.id,
          review: true,
        ),
      ).path,
    );
    expect(find.text('Unit 1 Garden · Lesson 1'), findsOneWidget);
    expect(courses.course.target(lesson.id, 'word-1')!.text, 'silver kite');
    expect(
      courses.course.target(lesson.id, 'word-1')!.kind,
      EnglishTargetKind.sentence,
    );
    expect(courses.course.target(lesson.id, 'word-1')!.role, 'Mother');
    expect(
      courses.course.target('unit-2-p2', 'river-word')!.text,
      'green boat',
    );
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });
  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('英语内容类型主题 Sheet ${subject.name} ${brightness.name}', (
        tester,
      ) async {
        final book = englishBook(), lesson = courses.course.lessons.single;
        await show(
          tester,
          EnglishTargetEditor(
            bookId: book.pdfSha256,
            lessonId: lesson.id,
            targetId: 'word-1',
          ),
          subject: subject,
          brightness: brightness,
          size: const Size(320, 740),
          textScale: 2,
        );
        await tester.tap(
          find.byKey(const ValueKey('english-content-type-selector')),
        );
        await tester.pumpAndSettle();
        expect(find.text('选择内容类型'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('english-content-type-selector')),
            matching: find.byType(InputDecorator),
          ),
          findsOneWidget,
        );
        expect(find.text('单词与短语'), findsWidgets);
        expect(find.text('练习与答案'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('字母'));
        await tester.pumpAndSettle();
        expect(find.text('字母'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await drainHiveWritesForTesting(tester);
      });
    }
  }
  testWidgets('课时审核按原书页展示图片，并按上到下、左到右编号', (tester) async {
    final book = englishBook();
    final lesson = courses.course.lessons.single.change({
      'targets': [
        EnglishTarget(
          id: 'lower-left',
          kind: EnglishTargetKind.sentence,
          text: 'Lower left',
          sources: [
            const EnglishSource(2, left: .1, top: .7, right: .4, bottom: .76),
          ],
        ).toJson(),
        EnglishTarget(
          id: 'upper-right',
          kind: EnglishTargetKind.sentence,
          text: 'Upper right',
          sources: [
            const EnglishSource(2, left: .6, top: .19, right: .9, bottom: .25),
          ],
        ).toJson(),
        EnglishTarget(
          id: 'upper-left',
          kind: EnglishTargetKind.sentence,
          text: 'Upper left',
          sources: [
            const EnglishSource(2, left: .1, top: .2, right: .4, bottom: .26),
          ],
        ).toJson(),
        EnglishTarget(
          id: 'next-page',
          kind: EnglishTargetKind.sentence,
          text: 'Next page',
          sources: [
            const EnglishSource(3, left: .2, top: .3, right: .8, bottom: .36),
          ],
        ).toJson(),
      ],
    });
    courses.course = englishCourse(book: book, lessons: [lesson]);

    await show(
      tester,
      EnglishLessonPage(
        bookId: book.pdfSha256,
        lessonId: lesson.id,
        review: true,
      ),
      size: const Size(390, 1600),
    );

    expect(find.text('Unit 1 Garden · Lesson 1'), findsOneWidget);
    expect(find.text('课时内容审核'), findsNothing);
    expect(find.byTooltip('补充内容'), findsOneWidget);
    expect(find.text('看原书'), findsNothing);
    expect(find.text('待核对提示'), findsNothing);
    expect(find.text('逐项核对'), findsNothing);
    expect(find.byKey(const ValueKey('review-source-page-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-source-page-3')), findsOneWidget);
    final imageCard = find
        .ancestor(
          of: find.byKey(const ValueKey('review-source-page-2')),
          matching: find.byType(ColoredCard),
        )
        .first;
    final textCard = find
        .ancestor(
          of: find.text('1. Upper left'),
          matching: find.byType(ColoredCard),
        )
        .first;
    expect(tester.element(imageCard), same(tester.element(textCard)));
    final first = tester.getTopLeft(find.text('1. Upper left'));
    final second = tester.getTopLeft(find.text('2. Upper right'));
    final third = tester.getTopLeft(find.text('3. Lower left'));
    final fourth = tester.getTopLeft(find.text('1. Next page'));
    expect(first.dy, lessThan(second.dy));
    expect(second.dy, lessThan(third.dy));
    expect(third.dy, lessThan(fourth.dy));

    for (final wideSize in [const Size(844, 390), const Size(1200, 900)]) {
      await show(
        tester,
        EnglishLessonPage(
          bookId: book.pdfSha256,
          lessonId: lesson.id,
          review: true,
        ),
        size: wideSize,
      );
      final firstPage = tester.getRect(
        find.byKey(const ValueKey('english-review-source-2')),
      );
      final secondPage = tester.getRect(
        find.byKey(const ValueKey('english-review-source-3')),
      );
      expect(firstPage.left, lessThan(secondPage.left));
      expect(firstPage.top, secondPage.top);
      expect(tester.takeException(), isNull);
    }

    final singlePageLesson = lesson.change({
      'endPage': 2,
      'targets': [
        for (final target in lesson.targets)
          if (target.sources.first.page == 2) target.toJson(),
      ],
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    courses.course = englishCourse(book: book, lessons: [singlePageLesson]);
    await show(
      tester,
      EnglishLessonPage(
        bookId: book.pdfSha256,
        lessonId: singlePageLesson.id,
        review: true,
      ),
      size: const Size(844, 390),
    );
    final singlePageCard = tester.getRect(
      find.byKey(const ValueKey('english-review-source-2')),
    );
    final sourceImage = tester.getRect(
      find.byKey(const ValueKey('review-source-page-2')),
    );
    expect(singlePageCard.width, lessThanOrEqualTo(560));
    expect(singlePageCard.center.dx, closeTo(422, 0.1));
    expect(sourceImage.width, singlePageCard.width);
    final firstEntry = tester.getRect(find.text('1. Upper left'));
    final secondEntry = tester.getRect(find.text('2. Upper right'));
    final thirdEntry = tester.getRect(find.text('3. Lower left'));
    expect(
      firstEntry.left,
      lessThan(secondEntry.left),
      reason:
          'single-page wide layout: first=$firstEntry second=$secondEntry card=${tester.getRect(find.byKey(const ValueKey('english-review-source-2')))}',
    );
    expect(firstEntry.top, secondEntry.top);
    expect(thirdEntry.top, greaterThan(secondEntry.top));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });
  testWidgets('课时审核先按原书卡片编号，再按卡片内行优先排序', (tester) async {
    final book = englishBook();
    final originalLesson = courses.course.lessons.single;
    Map<String, dynamic> sentence(
      String id,
      String text,
      double left,
      double top,
    ) => EnglishTarget(
      id: id,
      kind: EnglishTargetKind.sentence,
      text: text,
      sources: [
        EnglishSource(
          2,
          left: left,
          top: top,
          right: left + .2,
          bottom: top + .05,
        ),
      ],
    ).toJson();
    final lesson = originalLesson.change({
      'endPage': 2,
      'targets': [
        sentence('panel-3', 'Panel 3', .1, .50),
        sentence('panel-2-row-2', 'Panel 2 next row', .3, .30),
        sentence('panel-4', 'Panel 4', .65, .70),
        sentence('panel-2-right', 'Panel 2 right', .7, .205),
        sentence('panel-1', 'Panel 1', .1, .60),
        sentence('panel-2-left', 'Panel 2 left', .3, .20),
      ],
    });
    courses.course = englishCourse(book: book, lessons: [lesson]);

    await show(
      tester,
      EnglishLessonPage(
        bookId: book.pdfSha256,
        lessonId: lesson.id,
        review: true,
      ),
      size: const Size(1200, 1000),
      cardNumbers: {
        'panel-1': 1,
        'panel-2-left': 2,
        'panel-2-right': 2,
        'panel-2-row-2': 2,
        'panel-3': 3,
        'panel-4': 4,
      },
    );
    final orderedTexts = [
      '1. Panel 1',
      '2. Panel 2 left',
      '3. Panel 2 right',
      '4. Panel 2 next row',
      '5. Panel 3',
      '6. Panel 4',
    ];
    for (final (index, text) in orderedTexts.indexed) {
      expect(find.text(text), findsOneWidget);
      final previous = index == 0 ? null : find.text(orderedTexts[index - 1]);
      if (previous != null) {
        expect(
          tester.getCenter(find.text(text)).dy,
          greaterThanOrEqualTo(tester.getCenter(previous).dy),
          reason: '$text follows ${orderedTexts[index - 1]}',
        );
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });
  testWidgets('选择题保存当前作答，退出后从下一题继续，提交后产生真实活动', (tester) async {
    final book = englishBook();
    final router = GoRouter(
      initialLocation: AppRoutes.englishBookOf(
        book.pdfSha256,
        action: 'practice',
        kind: 'meaning',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, s) => EnglishPracticePage(
            bookId: s.pathParameters['id']!,
            kind: s.pathParameters['kind']!,
          ),
        ),
        GoRoute(
          path: AppRoutes.englishRecord,
          builder: (_, s) => EnglishHistoryPage(
            bookId: s.pathParameters['id']!,
            attemptId: s.pathParameters['attempt']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(
          theme: AppTheme.resolve(
            subject: AppSubject.poem,
            brightness: Brightness.light,
          ),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('词义练习'), findsOneWidget);
    expect(find.text('第 1 / 2 题'), findsNothing);
    expect(find.text('red kite'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('红风筝'));
    });
    await tester.pump();
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() async {
      await tester.tap(find.text('提交答案'));
    });
    await tester.pump();
    await until(tester, () => find.text('答对了').evaluate().isNotEmpty);
    expect(find.text('答对了'), findsOneWidget);
    await tester.tap(find.text('下一题'));
    await tester.pump();
    expect(find.text('第 2 / 2 题'), findsNothing);
    expect(find.text('blue bird'), findsOneWidget);
    // 重建该页面，读取已落盘的草稿。
    router.go('/missing');
    await tester.pumpAndSettle();
    router.go(
      AppRoutes.englishBookOf(
        book.pdfSha256,
        action: 'practice',
        kind: 'meaning',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 题'), findsNothing);
    expect(find.text('blue bird'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('蓝鸟'));
    });
    await tester.pump();
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() async {
      await tester.tap(find.text('提交答案'));
    });
    await tester.pump();
    await until(tester, () => find.text('答对了').evaluate().isNotEmpty);
    await tester.tap(find.text('查看本轮结果'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存本轮结果'));
    });
    await tester.pump();
    await until(tester, () => find.text('本次学习').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('本次学习'), findsOneWidget);
    expect(HiveBoxes.learningActivities.values.single.totalItems, 2);
    expect(HiveBoxes.learningActivities.values.single.successfulItems, 2);
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });
  testWidgets('英语整理审核页操作固定在底部且不显示书名和页覆盖摘要', (tester) async {
    final book = englishBook();
    await show(tester, EnglishCoursePage(bookId: book.pdfSha256, review: true));

    expect(find.text('英语整理与审核'), findsOneWidget);
    expect(find.text(book.title), findsNothing);
    expect(find.text('1 节课'), findsNothing);
    expect(find.text('已编辑内容会保留，新候选稿需逐课确认。'), findsNothing);
    expect(find.text('原书页覆盖'), findsNothing);
    expect(find.textContaining('页已归属，封面、目录和附录单独记录。'), findsNothing);
    expect(find.text('查看各页归属'), findsNothing);
    final organize = find.widgetWithText(FilledButton, '整理 / 继续');
    final extract = find.widgetWithText(OutlinedButton, '重新提取候选稿');
    expect(organize, findsOneWidget);
    expect(extract, findsOneWidget);
    expect(find.text('英语声音'), findsNothing);
    expect(
      tester.getRect(organize).top,
      closeTo(tester.getRect(extract).top, 1),
    );
    expect(tester.getRect(organize).left, closeTo(SpacingTokens.md, 1));
    expect(
      tester.getRect(extract).right,
      closeTo(tester.view.physicalSize.width - SpacingTokens.md, 1),
    );
    expect(
      tester.getRect(organize).width,
      closeTo(tester.getRect(extract).width, 1),
    );
    expect(tester.getRect(organize).bottom, greaterThan(600));

    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });
  test('旧页面仍在栈中时，切档案后重进使用独立音频会话', () async {
    final container = ProviderContainer(overrides: overrides());
    final book = englishBook(),
        oldKey = englishAudioKey(englishBook().pdfSha256);
    final lease = container.listen(englishAudioProvider(oldKey), (_, __) {});
    final old = lease.read();
    try {
      ProfileScope.switchTo('other-child');
      final fresh = container.read(
        englishAudioProvider(englishAudioKey(book.pdfSha256)),
      );
      expect(identical(fresh, old), isFalse);
      expect(fresh.profileId, 'other-child');
      expect(old.check, throwsStateError);
      expect(fresh.check, returnsNormally);
    } finally {
      lease.close();
      container.dispose();
      ProfileScope.reset();
    }
  });
  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('英语完整页面布局 ${subject.name} ${brightness.name} 窄屏大字与横屏', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final book = englishBook(), lesson = courses.course.lessons.single;
        final pages = <({Widget page, String text})>[
          (page: const EnglishTabPage(section: 'practice'), text: '练习'),
          (page: EnglishCoursePage(bookId: book.pdfSha256), text: '全书课程'),
          (
            page: EnglishCoursePage(bookId: book.pdfSha256, review: true),
            text: '英语整理与审核',
          ),
          (
            page: EnglishLessonPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
            ),
            text: '课时学习',
          ),
          (
            page: EnglishLessonPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              review: true,
            ),
            text: '${lesson.unitTitle} · ${lesson.title}',
          ),
          (
            page: EnglishStudyPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              kind: 'vocabulary',
            ),
            text: 'red kite',
          ),
          (
            page: EnglishSpeakingPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
            ),
            text: '跟读与回听',
          ),
          (page: EnglishPracticeHubPage(bookId: book.pdfSha256), text: '英语练习'),
          (
            page: EnglishPracticePage(bookId: book.pdfSha256, kind: 'meaning'),
            text: 'red kite',
          ),
          (
            page: EnglishHistoryPage(bookId: book.pdfSha256),
            text: '还没有已保存的英语记录',
          ),
          (
            page: EnglishTargetEditor(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              targetId: 'word-1',
            ),
            text: '编辑英语内容',
          ),
          (page: const EnglishVoicePage(), text: '英语声音'),
        ];
        for (final size in [const Size(320, 740), const Size(844, 390)]) {
          for (final entry in pages) {
            await show(
              tester,
              entry.page,
              subject: subject,
              brightness: brightness,
              size: size,
              textScale: 2,
            );
            expect(find.text(entry.text), findsWidgets, reason: entry.text);
            // 滚到底部，验证编辑/录音/练习页的操作也能到达。
            final scrollables = find.byType(Scrollable);
            if (scrollables.evaluate().isNotEmpty) {
              await tester.drag(scrollables.first, const Offset(0, -2500));
              await tester.pump();
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.text} $size',
            );
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          }
        }
        await drainHiveWritesForTesting(tester);
      });
    }
  }
}
