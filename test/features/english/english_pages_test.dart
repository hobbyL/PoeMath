import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/english_recording_store.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/english_course_page.dart';
import 'package:poemath/features/english/english_history_page.dart';
import 'package:poemath/features/english/english_practice_page.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_study_page.dart';
import 'package:poemath/features/english/english_tab_page.dart';
import 'package:poemath/features/english/english_target_editor.dart';
import 'package:poemath/features/english/english_widgets.dart';
import 'package:poemath/features/english/widgets/english_spelling_practice_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_learning_providers.dart';

import '../../helpers/english_fixture.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
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

class _Progress extends EnglishProgressRepository {
  _Progress(super.book, super.courses, {this.beforeRemember});
  final Future<void> Function()? beforeRemember;

  @override
  EnglishProgress load() => EnglishProgress(
    profileId: profileId,
    bookId: book.pdfSha256,
    editionId: book.learningEditionId,
  );

  @override
  Future<void> remember(String lessonId, {String? targetId}) async {
    await beforeRemember?.call();
  }
}

class _RetryProgress extends EnglishProgressRepository {
  _RetryProgress(super.book, super.courses);
  int calls = 0;

  @override
  Future<void> complete(EnglishAttempt attempt) async {
    if (++calls == 1) throw StateError('保存失败，请重试');
    await super.complete(attempt);
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
    subjectTextbooksProvider(TextbookSubject.english)
        .overrideWithValue([englishBook()]),
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
  EnglishSpellingPracticeContent spellingContent(WidgetTester tester) =>
      tester.widget<EnglishSpellingPracticeContent>(
        find.byType(EnglishSpellingPracticeContent),
      );
  String spellingInput(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('english-spelling-input')))
      .data!;
  Future<void> chooseSpelling(WidgetTester tester, String text) async {
    for (final letter in text.split('')) {
      final content = spellingContent(tester);
      final index = content.question.options
          .asMap()
          .entries
          .firstWhere(
            (entry) =>
                entry.value == letter && !content.tokens.contains(entry.key),
          )
          .key;
      final token = find.byKey(ValueKey('english-token-$index'));
      await tester.ensureVisible(token);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(token));
      await tester.pump();
      await until(tester, () => !spellingContent(tester).busy);
    }
  }

  testWidgets('英语 Tab 暂时仅保留课本入口', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, const EnglishTabPage());

    final title = find.text('课本(1)');
    expect(title, findsOneWidget);
    expect(
      tester.getCenter(title).dx,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        1,
      ),
    );
    expect(find.text('练习'), findsNothing);
    expect(find.text('复习'), findsNothing);
    expect(find.byType(EnglishPracticeHubPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('自动整理词汇直接进入词表和单词练习，不再显示翻卡及模式切换', (tester) async {
    final book = englishBook();
    final sourceLesson = courses.course.lessons.single;
    final lesson = sourceLesson.change({
      'targets': [
        for (final target in sourceLesson.targets)
          (target.kind == EnglishTargetKind.vocabulary
                  ? target.change({'reviewDigest': null, 'audioReview': null})
                  : target)
              .toJson(),
      ],
    });
    courses.course = englishCourse(book: book, lessons: [lesson]);
    final router = GoRouter(
      initialLocation: AppRoutes.englishBookOf(
        book.pdfSha256,
        lesson: lesson.id,
        action: 'content',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.englishLessonContent,
          builder: (_, state) => EnglishLessonPage(
            bookId: state.pathParameters['id']!,
            lessonId: state.pathParameters['lesson']!,
            sourceContent: true,
          ),
        ),
        GoRoute(
          path: AppRoutes.englishStudy,
          builder: (_, state) => EnglishStudyPage(
            bookId: state.pathParameters['id']!,
            lessonId: state.pathParameters['lesson']!,
            kind: state.uri.queryParameters['kind'],
          ),
        ),
        GoRoute(
          path: AppRoutes.englishVocabulary,
          builder: (_, state) => EnglishStudyPage(
            bookId: state.pathParameters['id']!,
            lessonId: state.pathParameters['lesson']!,
            kind: 'vocabulary',
            targetId: state.pathParameters['target']!,
          ),
        ),
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, state) => EnglishPracticePage(
            bookId: state.pathParameters['id']!,
            kind: state.pathParameters['kind']!,
            lessonId: state.uri.queryParameters['lesson'],
            targetKey: state.uri.queryParameters['targetKey'],
          ),
        ),
        GoRoute(
          path: AppRoutes.englishSource,
          builder: (_, state) =>
              Scaffold(body: Text('原书第 ${state.pathParameters['page']} 页')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          englishProgressRepositoryProvider.overrideWith((ref, id) {
            final book = ref.watch(englishBookProvider(id));
            if (book == null) return null;
            return _Progress(book, courses);
          }),
        ],
        child: MaterialApp.router(
          theme: AppTheme.resolve(
            subject: AppSubject.poem,
            brightness: Brightness.light,
          ),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('english-vocabulary-entry'));
    expect(entry, findsOneWidget);
    expect(tester.widget<AppTile>(entry).onTap, isNotNull);
    expect(find.text('2 项可学'), findsOneWidget);
    await tester.ensureVisible(find.text('单词与短语'));
    await tester.tap(find.text('单词与短语'));
    await tester.pumpAndSettle();
    final vocabularyPage = find.byType(EnglishStudyPage);
    expect(vocabularyPage, findsOneWidget);
    expect(tester.widget<EnglishStudyPage>(vocabularyPage).kind, 'vocabulary');
    expect(find.text('红风筝'), findsOneWidget);
    expect(find.byTooltip('朗读 red kite'), findsOneWidget);
    expect(find.text('${lesson.unitTitle} · ${lesson.title}'), findsNothing);
    expect(find.text('词义选择'), findsNothing);
    expect(find.text('拼写练习'), findsNothing);
    expect(
      find.byKey(const ValueKey('english-vocabulary-self-mastered')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('english-vocabulary-self-again')),
      findsNothing,
    );

    await tester.tap(find.text('red kite'));
    await tester.pumpAndSettle();
    expect(find.text('单词详情'), findsOneWidget);
    expect(find.text('red kite'), findsOneWidget);
    expect(find.text('blue bird'), findsNothing);
    expect(find.text('翻卡自测'), findsNothing);
    expect(find.text('词义选择'), findsOneWidget);
    expect(find.text('拼写练习'), findsOneWidget);
    expect(find.text('听一听'), findsNothing);
    expect(find.text('看原书'), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byTooltip('听一听')),
      findsOneWidget,
    );

    final meaningEntry = find.byKey(
      const ValueKey('english-vocabulary-meaning-practice'),
    );
    await tester.ensureVisible(meaningEntry);
    await tester.tap(find.text('词义选择'));
    await tester.pumpAndSettle();
    final meaningPractice = find.byType(EnglishPracticePage);
    expect(meaningPractice, findsOneWidget);
    expect(tester.widget<EnglishPracticePage>(meaningPractice).kind, 'meaning');
    expect(
      tester.widget<EnglishPracticePage>(meaningPractice).lessonId,
      lesson.id,
    );
    expect(
      tester.widget<EnglishPracticePage>(meaningPractice).targetKey,
      '${lesson.id}/word-1/meaning',
    );
    expect(find.text('red kite'), findsOneWidget);
    expect(find.text('blue bird'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('红风筝'));
    });
    await tester.pump();
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() async {
      await tester.tap(find.text('提交答案'));
    });
    await tester.pump();
    await until(
      tester,
      () => find.byIcon(Icons.check_circle_outline).evaluate().isNotEmpty,
    );
    expect(find.text('完成练习'), findsOneWidget);
    expect(find.text('下一题'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('单词详情'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('翻卡自测'), findsNothing);
    expect(find.byKey(const ValueKey('english-vocabulary-mode')), findsNothing);
    expect(
      tester.widget<AppScaffold>(find.byType(AppScaffold)).bottomNavigationBar,
      isNull,
    );
    expect(find.text('词义选择'), findsNothing);
    await tester.tap(find.text('blue bird'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('english-vocabulary-meaning-practice')),
    );
    expect(find.text('词义选择'), findsOneWidget);
    expect(find.text('拼写练习'), findsOneWidget);
    await tester.tap(find.text('拼写练习'));
    await tester.pumpAndSettle();
    final spellingPractice = find.byType(EnglishPracticePage);
    expect(spellingPractice, findsOneWidget);
    expect(
      tester.widget<EnglishPracticePage>(spellingPractice).kind,
      'spelling',
    );
    expect(
      tester.widget<EnglishPracticePage>(spellingPractice).lessonId,
      lesson.id,
    );
    expect(
      tester.widget<EnglishPracticePage>(spellingPractice).targetKey,
      '${lesson.id}/word-2/spelling',
    );
    expect(find.text('蓝鸟'), findsOneWidget);
    expect(find.text('红风筝'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('单词详情整卡和导航可播放，正常状态不显示文字，异常可重试', (tester) async {
    final book = englishBook(), lesson = courses.course.lessons.single;
    final synth = NarrationSynth();
    final players = <RecordingNarrationPlayer>[];
    Map<String, String>? voice = {'locale': 'en-US', 'name': 'test'};
    final tts = TtsService(
      NarrationSettings(),
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final player = RecordingNarrationPlayer();
        players.add(player);
        return player;
      },
    );
    addTearDown(tts.dispose);
    final container = ProviderContainer(
      overrides: [
        ...overrides(),
        englishVoiceProvider.overrideWith((ref) => voice),
        englishProgressRepositoryProvider.overrideWith(
          (ref, id) => _Progress(book, courses),
        ),
        englishAudioProvider.overrideWith(
          (ref, key) => EnglishAudio(
            bookId: key.$1,
            tts: tts,
            cache: MemoryNarrationCache(),
            store: EnglishRecordingStore(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: EnglishStudyPage(
            bookId: book.pdfSha256,
            lessonId: lesson.id,
            kind: 'vocabulary',
            targetId: 'word-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('english-vocabulary-playback'));
    expect(
      find.descendant(of: find.byType(AppBar), matching: button),
      findsOneWidget,
    );
    expect(tester.widget<IconButton>(button).tooltip, '听一听');
    await tester.runAsync(() => tester.tap(button));
    await until(
      tester,
      () => players.isNotEmpty && players.single.audio.isNotEmpty,
    );
    expect(synth.texts, ['red kite']);
    expect(tester.widget<IconButton>(button).tooltip, '停止朗读');
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    await tester.runAsync(() => tester.tap(button));
    await tester.pumpAndSettle();
    expect(players.single.disposed, isTrue);
    expect(tester.widget<IconButton>(button).tooltip, '听一听');
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    final card = find.byKey(const ValueKey('english-vocabulary-detail-card'));
    final practice = find.byKey(
      const ValueKey('english-vocabulary-meaning-practice'),
    );
    final practiceBounds = tester.getRect(practice);
    for (final position in [
      tester.getCenter(find.text('red kite')),
      tester.getCenter(find.text('红风筝')),
      tester.getTopLeft(card) + const Offset(8, 8),
    ]) {
      final expectedPlayers = players.length + 1;
      await tester.runAsync(() => tester.tapAt(position));
      await until(
        tester,
        () =>
            players.length == expectedPlayers && players.last.audio.isNotEmpty,
      );
      expect(find.text('准备英语示范'), findsNothing);
      expect(tester.widget<IconButton>(button).tooltip, '停止朗读');
      await tester.runAsync(() async => players.last.starts.single());
      await tester.pump();
      expect(find.text('正在播放英语示范'), findsNothing);
      expect(tester.getRect(practice), practiceBounds);
      await tester.runAsync(() async => players.last.ends.single.complete());
      await until(
        tester,
        () => tester.widget<IconButton>(button).tooltip == '听一听',
      );
      expect(find.text('示范播放完成'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.getRect(practice), practiceBounds);
      expect(synth.texts, ['red kite']);
    }

    voice = null;
    container.invalidate(englishVoiceProvider);
    await tester.pump();
    await tester.runAsync(() => tester.tap(button));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('暂无英语音色，可在“英语声音”中选择或安装语音包'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<IconButton>(button).tooltip, '听一听');
    expect(tester.getRect(practice), practiceBounds);

    courses.course = englishCourse(
      book: book,
      lessons: [englishLesson(targets: [])],
    );
    container.invalidate(englishCourseProvider(book.pdfSha256));
    await tester.pumpAndSettle();
    expect(find.text('这个词暂不可学习'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(synth.texts, ['red kite']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('词表朗读复用缓存，离页取消音频和等待保存位置的播放请求', (tester) async {
    final book = englishBook(), lesson = courses.course.lessons.single;
    final synth = NarrationSynth();
    final players = <RecordingNarrationPlayer>[];
    Completer<void>? pendingRemember;
    final progress = _Progress(
      book,
      courses,
      beforeRemember: () async => await pendingRemember?.future,
    );
    final tts = TtsService(
      NarrationSettings(),
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final player = RecordingNarrationPlayer();
        players.add(player);
        return player;
      },
    );
    addTearDown(tts.dispose);
    final container = ProviderContainer(
      overrides: [
        ...overrides(),
        englishVoiceProvider.overrideWith(
          (ref) => {'locale': 'en-US', 'name': 'test'},
        ),
        englishProgressRepositoryProvider.overrideWith((ref, id) => progress),
        englishAudioProvider.overrideWith(
          (ref, key) => EnglishAudio(
            bookId: key.$1,
            tts: tts,
            cache: MemoryNarrationCache(),
            store: EnglishRecordingStore(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    Future<void> openList() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: EnglishStudyPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              kind: 'vocabulary',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openList();
    final play = find.byTooltip('朗读 red kite');
    await tester.runAsync(() => tester.tap(play));
    await until(
      tester,
      () => players.isNotEmpty && players.last.audio.isNotEmpty,
    );
    expect(synth.texts, ['red kite']);
    await tester.runAsync(() => tester.tap(find.byTooltip('停止朗读')));
    await tester.pumpAndSettle();
    expect(players.last.disposed, isTrue);
    await tester.runAsync(() => tester.tap(play));
    await until(
      tester,
      () => players.length == 2 && players.last.audio.isNotEmpty,
    );
    expect(synth.texts, ['red kite']);
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpAndSettle();
    expect(players.last.disposed, isTrue);

    await openList();
    pendingRemember = Completer<void>();
    await tester.tap(play);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pendingRemember.complete();
    await tester.pumpAndSettle();
    expect(players, hasLength(2));
    expect(synth.texts, ['red kite']);
  });

  testWidgets('单词详情练习入口四主题并排，大字号可换行且导航播放固定可达', (tester) async {
    addTearDown(tester.view.reset);
    final book = englishBook(), lesson = courses.course.lessons.single;
    for (final subject in AppSubject.values) {
      for (final brightness in Brightness.values) {
        for (final layout in [
          (size: const Size(360, 780), scale: 1.0, columns: 2),
          (size: const Size(390, 844), scale: 1.0, columns: 2),
          (size: const Size(320, 740), scale: 2.0, columns: 1),
          (size: const Size(844, 390), scale: 1.0, columns: 2),
          (size: const Size(844, 390), scale: 2.0, columns: 1),
        ]) {
          await show(
            tester,
            EnglishStudyPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              kind: 'vocabulary',
              targetId: 'word-1',
            ),
            subject: subject,
            brightness: brightness,
            size: layout.size,
            textScale: layout.scale,
          );
          final playback = find.byKey(
            const ValueKey('english-vocabulary-playback'),
          );
          expect(playback.hitTestable(), findsOneWidget);
          expect(find.text('听一听'), findsNothing);
          expect(find.text('看原书'), findsNothing);
          final meaning = tester.getRect(
            find.byKey(const ValueKey('english-vocabulary-meaning-practice')),
          );
          final spelling = tester.getRect(
            find.byKey(const ValueKey('english-vocabulary-spelling-practice')),
          );
          expect(meaning.width, closeTo(spelling.width, .01));
          if (layout.columns == 2) {
            expect(meaning.top, closeTo(spelling.top, .01));
            expect(spelling.left - meaning.right, closeTo(8, .01));
          } else {
            expect(spelling.top, greaterThan(meaning.bottom));
          }
          final playbackBounds = tester.getRect(playback);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -1000),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(playback), playbackBounds);
          expect(playback.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  });

  testWidgets('词表四主题竖屏双列、横屏三列，大字减少列数且正文占满可用高度', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final book = englishBook();
    final lesson = englishLesson(
      targets: [
        for (var i = 0; i < 12; i++)
          englishWord(
            id: 'word-$i',
            text: switch (i) {
              0 => 'grandmother',
              1 => 'take care of your family',
              _ => 'vocabulary $i',
            },
          ),
      ],
    );
    courses.course = englishCourse(book: book, lessons: [lesson]);
    for (final subject in AppSubject.values) {
      for (final brightness in Brightness.values) {
        for (final layout in [
          (size: const Size(320, 740), scale: 2.0, columns: 1),
          (size: const Size(360, 780), scale: 1.0, columns: 2),
          (size: const Size(390, 844), scale: 1.0, columns: 2),
          (size: const Size(390, 844), scale: 1.5, columns: 1),
          (size: const Size(844, 390), scale: 1.0, columns: 3),
          (size: const Size(844, 390), scale: 2.0, columns: 2),
        ]) {
          await show(
            tester,
            EnglishStudyPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              kind: 'vocabulary',
            ),
            subject: subject,
            brightness: brightness,
            size: layout.size,
            textScale: layout.scale,
          );
          final list = find.byKey(
            const ValueKey('english-vocabulary-learning'),
          );
          expect(find.text('翻卡自测'), findsNothing);
          expect(
            find.byKey(const ValueKey('english-vocabulary-mode')),
            findsNothing,
          );
          expect(
            tester
                .widget<AppScaffold>(find.byType(AppScaffold))
                .bottomNavigationBar,
            isNull,
          );
          expect(tester.getRect(list).bottom, closeTo(layout.size.height, 1));
          final first = tester.getRect(
            find.byKey(const ValueKey('english-vocabulary-word-word-0')),
          );
          final second = tester.getRect(
            find.byKey(const ValueKey('english-vocabulary-word-word-1')),
          );
          final firstArrow = tester.getRect(
            find.descendant(
              of: find.byKey(const ValueKey('english-vocabulary-word-word-0')),
              matching: find.byIcon(Icons.chevron_right),
            ),
          );
          expect(first.right - firstArrow.right, closeTo(8, .01));
          expect(firstArrow.size, const Size(24, 24));
          final playback = find.descendant(
            of: find.byKey(const ValueKey('english-vocabulary-word-word-0')),
            matching: find.byType(IconButton),
          );
          final playbackIcon = tester.getRect(
            find.descendant(
              of: playback,
              matching: find.byIcon(Icons.volume_up_outlined),
            ),
          );
          expect(firstArrow.left - playbackIcon.right, closeTo(8, .01));
          expect(tester.getSize(playback).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(playback).height, greaterThanOrEqualTo(44));
          final word = find.text('grandmother');
          final wordBounds = tester.getRect(word);
          expect(wordBounds.bottom, lessThan(tester.getRect(playback).top));
          final paragraph = tester.renderObject<RenderParagraph>(word);
          expect(
            paragraph.constraints.maxWidth,
            closeTo(first.width - 24, .01),
            reason: '文字独占卡片内容宽度，不能再扣除播放和箭头所占空间',
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          for (final box in paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 11),
          )) {
            expect(box.left, greaterThanOrEqualTo(-.1));
            expect(box.right, lessThanOrEqualTo(wordBounds.width + .1));
            expect(box.bottom, lessThanOrEqualTo(wordBounds.height + .1));
          }
          if (layout.columns > 1) {
            expect(first.top, closeTo(second.top, 1));
            expect(first.right, lessThan(second.left));
            expect(first.width, lessThan(layout.size.width / layout.columns));
            for (var column = 1; column < layout.columns; column++) {
              final card = tester.getRect(
                find.byKey(ValueKey('english-vocabulary-word-word-$column')),
              );
              expect(card.top, closeTo(first.top, 1));
              expect(card.left, greaterThan(first.right));
            }
            final nextRow = tester.getRect(
              find.byKey(
                ValueKey('english-vocabulary-word-word-${layout.columns}'),
              ),
            );
            expect(nextRow.top, greaterThan(first.top));
          } else {
            expect(second.top, greaterThan(first.bottom));
          }
          await tester.drag(list, const Offset(0, -2000));
          await tester.pumpAndSettle();
          expect(find.text('vocabulary 11').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  });
  testWidgets('手工新增且未审核的词汇不出现在孩子端', (tester) async {
    final book = englishBook(),
        lesson = courses.course.lessons.single.change({
          'targets': [englishWord(approved: false, origin: 'parent').toJson()],
        });
    courses.course = englishCourse(book: book, lessons: [lesson]);
    await show(
      tester,
      EnglishLessonPage(
        bookId: book.pdfSha256,
        lessonId: lesson.id,
        sourceContent: true,
      ),
    );
    expect(
      find.byKey(const ValueKey('english-vocabulary-entry')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
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
  testWidgets('拼写恢复旧字母草稿，切词独立保存，撤回清空与提示证据兼容且失败可重试', (tester) async {
    final book = englishBook();
    final progress = _RetryProgress(book, courses);
    final question = buildEnglishQuestions(
      courses.course,
      EnglishPracticeKind.spelling,
    ).first;
    final scope =
        '${book.pdfSha256}/unit-1-p2/spelling/false/false/${question.recordKey}';
    final drafts = PracticeDraftRepository();
    drafts.claim('englishPractice', scope: scope);
    await tester.runAsync(
      () => drafts.save('englishPractice', {
        'sessionId': 'legacy-spelling',
        'questions': [question.toJson()],
        'answers': <Object>[],
        'input': '',
        'tokens': [question.options.indexOf('r')],
        'hint': true,
        'seconds': 2,
      }, scope: scope),
    );
    final path = AppRoutes.englishBookOf(
      book.pdfSha256,
      action: 'practice',
      kind: 'spelling',
      lesson: 'unit-1-p2',
      targetKey: question.recordKey,
    );
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, state) => EnglishPracticePage(
            key: ValueKey(state.uri.toString()),
            bookId: state.pathParameters['id']!,
            kind: state.pathParameters['kind']!,
            lessonId: state.uri.queryParameters['lesson'],
            targetKey: state.uri.queryParameters['targetKey'],
          ),
        ),
        GoRoute(
          path: AppRoutes.englishRecord,
          builder: (_, _) => const Scaffold(body: Text('保存完成')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          englishProgressRepositoryProvider.overrideWith((ref, id) => progress),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('拼写练习'), findsNothing);
    expect(find.text('红风筝'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('红风筝')),
      findsOneWidget,
    );
    expect(find.text('red kite'), findsNothing);
    expect(spellingInput(tester), 'r');
    expect(submitReady(tester), isFalse);
    final practiceState = tester.state(find.byType(EnglishPracticePage));
    final scaffold = tester.element(find.byType(AppScaffold));
    final location = router.routeInformationProvider.value.uri;
    final actions = tester.getRect(
      find.byKey(const ValueKey('english-spelling-actions')),
    );
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(
      tester,
      () => spellingContent(tester).question.target.id == 'word-2',
    );
    await tester.pumpAndSettle();
    expect(spellingInput(tester), '点选字母');
    expect(tester.state(find.byType(EnglishPracticePage)), same(practiceState));
    expect(tester.element(find.byType(AppScaffold)), same(scaffold));
    expect(router.routeInformationProvider.value.uri, location);
    expect(
      tester.getRect(find.byKey(const ValueKey('english-spelling-actions'))),
      actions,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('蓝鸟')),
      findsOneWidget,
    );
    await chooseSpelling(tester, 'b');
    await tester.runAsync(() => tester.tap(find.byTooltip('上一题')));
    await until(
      tester,
      () => spellingContent(tester).question.target.id == 'word-1',
    );
    await tester.pumpAndSettle();
    expect(spellingInput(tester), 'r');
    expect(HiveBoxes.learningActivities.values, isEmpty);
    await tester.runAsync(() => tester.tap(find.byTooltip('撤回一个字母')));
    await until(tester, () => spellingInput(tester) == '点选字母');
    await chooseSpelling(tester, 're');
    await tester.runAsync(() => tester.tap(find.text('清空')));
    await until(tester, () => spellingInput(tester) == '点选字母');
    await chooseSpelling(tester, 'red kite');
    expect(spellingContent(tester).tokens.toSet(), hasLength(8));
    expect(submitReady(tester), isTrue);
    await tester.runAsync(() => tester.tap(find.text('提交答案')));
    await until(tester, () => find.text('完成练习').evaluate().isNotEmpty);
    expect(spellingInput(tester), 'red kite');
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.text('答对了'), findsNothing);
    await tester.runAsync(() => tester.tap(find.text('完成练习')));
    await until(tester, () => find.text('保存失败，请重试').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SnackBar), const Offset(0, 100));
    await tester.pumpAndSettle();
    router.go('/missing');
    await tester.pumpAndSettle();
    router.go(path);
    await tester.pumpAndSettle();
    expect(spellingInput(tester), 'red kite');
    expect(find.text('完成练习'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('完成练习')));
    await until(tester, () => find.text('保存完成').evaluate().isNotEmpty);
    final attempt = progress.load().attempts.single;
    expect(attempt.id, 'legacy-spelling');
    expect(attempt.answers.single.answer, 'red kite');
    expect(attempt.answers.single.hinted, isTrue);
    expect(attempt.answers.single.objectiveCorrect, isFalse);
    expect(HiveBoxes.learningActivities.values.single.totalItems, 1);
    expect(HiveBoxes.learningActivities.values.single.successfulItems, 0);
    expect(drafts.get('englishPractice', scope: scope), isNull);
    final other = drafts.get(
      'englishPractice',
      scope:
          '${book.pdfSha256}/unit-1-p2/spelling/false/false/unit-1-p2/word-2/spelling',
    )!;
    expect(other['answers'], isEmpty);
    expect(other['tokens'], hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('拼写整组允许乱序切词，答错在原卡核对，跳过和成绩仅记录各自单词', (tester) async {
    final book = englishBook();
    final path = AppRoutes.englishBookOf(
      book.pdfSha256,
      action: 'practice',
      kind: 'spelling',
    );
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, _) =>
              EnglishPracticePage(bookId: book.pdfSha256, kind: 'spelling'),
        ),
        GoRoute(
          path: AppRoutes.englishRecord,
          builder: (_, _) => const Scaffold(body: Text('保存完成')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await chooseSpelling(tester, 'r');
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(
      tester,
      () => spellingContent(tester).question.target.id == 'word-2',
    );
    await chooseSpelling(tester, 'drib eulb');
    await tester.runAsync(() => tester.tap(find.text('提交答案')));
    await until(tester, () => find.text('继续练习').evaluate().isNotEmpty);
    expect(spellingInput(tester), 'drib eulb');
    expect(find.text('blue bird'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    router.go('/missing');
    await tester.pumpAndSettle();
    router.go(path);
    await tester.pumpAndSettle();
    expect(spellingContent(tester).question.target.id, 'word-2');
    expect(spellingInput(tester), 'drib eulb');
    await tester.runAsync(() => tester.tap(find.text('继续练习')));
    await until(
      tester,
      () => spellingContent(tester).question.target.id == 'word-1',
    );
    expect(spellingInput(tester), 'r');
    await tester.runAsync(() => tester.tap(find.text('跳过')));
    await until(tester, () => find.text('完成练习').evaluate().isNotEmpty);
    expect(find.text('red kite'), findsOneWidget);
    expect(find.text('答对了'), findsNothing);
    await tester.runAsync(() => tester.tap(find.text('完成练习')));
    await until(tester, () => find.text('保存完成').evaluate().isNotEmpty);
    final answers = EnglishProgressRepository(
      book,
      courses,
    ).load().attempts.single.answers;
    expect(answers.map((a) => a.question.target.id), ['word-2', 'word-1']);
    expect(answers.first.correct, isFalse);
    expect(answers.last.skipped, isTrue);
    expect(answers.last.correct, isNull);
    expect(HiveBoxes.learningActivities.values.single.totalItems, 2);
    expect(HiveBoxes.learningActivities.values.single.successfulItems, 0);
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('单词练习原页切换保留独立草稿和底栏位置，返回仍到原入口', (tester) async {
    final book = englishBook();
    final firstPath = AppRoutes.englishBookOf(
      book.pdfSha256,
      action: 'practice',
      kind: 'meaning',
      lesson: 'unit-1-p2',
      targetKey: 'unit-1-p2/word-1/meaning',
    );
    final router = GoRouter(
      initialLocation: '/origin',
      routes: [
        GoRoute(
          path: '/origin',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(firstPath),
              child: const Text('单词详情入口'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, state) => EnglishPracticePage(
            key: ValueKey(state.uri.toString()),
            bookId: state.pathParameters['id']!,
            kind: state.pathParameters['kind']!,
            lessonId: state.uri.queryParameters['lesson'],
            targetKey: state.uri.queryParameters['targetKey'],
          ),
        ),
        GoRoute(
          path: AppRoutes.englishRecord,
          builder: (_, _) => const Scaffold(body: Text('保存完成')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('单词详情入口'));
    await tester.pumpAndSettle();
    final practiceState = tester.state(find.byType(EnglishPracticePage));
    final scaffold = tester.element(find.byType(AppScaffold));
    final location = router.routeInformationProvider.value.uri;
    final actions = tester.getRect(
      find.byKey(const ValueKey('english-meaning-actions')),
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('red kite')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_left),
          )
          .onPressed,
      isNull,
    );
    await tester.runAsync(() => tester.tap(find.text('红风筝')));
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(tester, () => find.text('blue bird').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EnglishPracticePage)), same(practiceState));
    expect(tester.element(find.byType(AppScaffold)), same(scaffold));
    expect(router.routeInformationProvider.value.uri, location);
    expect(
      tester.getRect(find.byKey(const ValueKey('english-meaning-actions'))),
      actions,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );
    expect(submitReady(tester), isFalse);
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    await tester.runAsync(() => tester.tap(find.text('蓝鸟')));
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() => tester.tap(find.byTooltip('上一题')));
    await until(tester, () => find.text('red kite').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(submitReady(tester), isTrue);
    final drafts = PracticeDraftRepository();
    final prefix = '${book.pdfSha256}/unit-1-p2/meaning/false/false';
    final first = drafts.get(
      'englishPractice',
      scope: '$prefix/unit-1-p2/word-1/meaning',
    )!;
    final second = drafts.get(
      'englishPractice',
      scope: '$prefix/unit-1-p2/word-2/meaning',
    )!;
    expect(first['input'], '红风筝');
    expect(second['input'], '蓝鸟');
    expect(first['answers'], isEmpty);
    expect(second['answers'], isEmpty);
    expect(first['sessionId'], isNot(second['sessionId']));
    expect(HiveBoxes.learningActivities.values, isEmpty);
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(tester, () => find.text('blue bird').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(submitReady(tester), isTrue);
    await tester.runAsync(() => tester.tap(find.text('提交答案')));
    await until(tester, () => find.text('完成练习').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.byTooltip('上一题')));
    await until(tester, () => find.text('red kite').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(submitReady(tester), isTrue);
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(tester, () => find.text('blue bird').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('完成练习'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('完成练习')));
    await until(tester, () => find.text('保存完成').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    final attempt = EnglishProgressRepository(
      book,
      courses,
    ).load().attempts.single;
    expect(attempt.id, second['sessionId']);
    expect(attempt.answers.single.question.target.id, 'word-2');
    expect(HiveBoxes.learningActivities.values.single.totalItems, 1);
    expect(HiveBoxes.learningActivities.values.single.successfulItems, 1);
    expect(
      drafts.get('englishPractice', scope: '$prefix/unit-1-p2/word-2/meaning'),
      isNull,
    );
    expect(
      drafts.get(
        'englishPractice',
        scope: '$prefix/unit-1-p2/word-1/meaning',
      )!['input'],
      '红风筝',
    );
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('单词详情入口'), findsOneWidget);
    expect(router.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('整组词义练习可未作答切词，乱序提交后恢复位置和正确归属', (tester) async {
    final book = englishBook();
    final practicePath = AppRoutes.englishBookOf(
      book.pdfSha256,
      action: 'practice',
      kind: 'meaning',
    );
    final router = GoRouter(
      initialLocation: practicePath,
      routes: [
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, _) =>
              EnglishPracticePage(bookId: book.pdfSha256, kind: 'meaning'),
        ),
        GoRoute(
          path: AppRoutes.englishRecord,
          builder: (_, _) => const Scaffold(body: Text('保存完成')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('红风筝')));
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(tester, () => find.text('blue bird').evaluate().isNotEmpty);
    expect(submitReady(tester), isFalse);
    expect(HiveBoxes.learningActivities.values, isEmpty);
    await tester.runAsync(() => tester.tap(find.text('蓝鸟')));
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() => tester.tap(find.text('提交答案')));
    await until(tester, () => find.text('继续练习').evaluate().isNotEmpty);
    router.go('/missing');
    await tester.pumpAndSettle();
    router.go(practicePath);
    await tester.pumpAndSettle();
    expect(find.text('blue bird'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.byTooltip('上一题')));
    await until(tester, () => find.text('red kite').evaluate().isNotEmpty);
    expect(submitReady(tester), isTrue);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('提交答案')));
    await until(tester, () => find.text('完成练习').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('完成练习')));
    await until(tester, () => find.text('保存完成').evaluate().isNotEmpty);
    final answers = EnglishProgressRepository(
      book,
      courses,
    ).load().attempts.single.answers;
    expect(answers.map((a) => a.question.target.id), ['word-2', 'word-1']);
    expect(answers.every((a) => a.objectiveCorrect && !a.skipped), isTrue);
    expect(HiveBoxes.learningActivities.values.single.totalItems, 2);
    expect(HiveBoxes.learningActivities.values.single.successfulItems, 2);
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
    expect(find.text('词义选择'), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('red kite')),
      findsOneWidget,
    );
    expect(find.text('第 1 / 2 题'), findsNothing);
    expect(find.text('red kite'), findsOneWidget);
    expect(submitReady(tester), isFalse);
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('红风筝'));
    });
    await tester.pump();
    await until(tester, () => submitReady(tester));
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
    expect(find.text('red kite'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(submitReady(tester), isTrue);
    await tester.runAsync(() async {
      await tester.tap(find.text('提交答案'));
    });
    await tester.pump();
    await until(
      tester,
      () => find.byIcon(Icons.check_circle_outline).evaluate().isNotEmpty,
    );
    expect(find.text('答对了'), findsNothing);
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(tester, () => find.text('blue bird').evaluate().isNotEmpty);
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
    await until(
      tester,
      () => find.byIcon(Icons.check_circle_outline).evaluate().isNotEmpty,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('完成练习'));
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
  testWidgets('旧词义提示草稿仍不计独立答对，保存失败可从末题草稿重试', (tester) async {
    final book = englishBook();
    final progress = _RetryProgress(book, courses);
    const targetKey = 'unit-1-p2/word-1/meaning';
    final practicePath = AppRoutes.englishBookOf(
      book.pdfSha256,
      action: 'practice',
      kind: 'meaning',
      lesson: 'unit-1-p2',
      targetKey: targetKey,
    );
    // 兼容移除“看提示”入口前留下的草稿，不能把旧提示作答当作独立答对。
    final legacyQuestion = buildEnglishQuestions(
      courses.course,
      EnglishPracticeKind.meaning,
      lessonId: 'unit-1-p2',
      targetKeys: {targetKey},
    ).single;
    final legacyDrafts = PracticeDraftRepository();
    final legacyScope =
        '${book.pdfSha256}/unit-1-p2/meaning/false/false/$targetKey';
    legacyDrafts.claim('englishPractice', scope: legacyScope);
    await tester.runAsync(
      () => legacyDrafts.save('englishPractice', {
        'sessionId': 'legacy-hinted-meaning',
        'questions': [legacyQuestion.toJson()],
        'answers': <Object>[],
        'input': '',
        'tokens': <int>[],
        'hint': true,
        'seconds': 0,
      }, scope: legacyScope),
    );
    final router = GoRouter(
      initialLocation: practicePath,
      routes: [
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, state) => EnglishPracticePage(
            bookId: state.pathParameters['id']!,
            kind: state.pathParameters['kind']!,
            lessonId: state.uri.queryParameters['lesson'],
            targetKey: state.uri.queryParameters['targetKey'],
          ),
        ),
        GoRoute(
          path: AppRoutes.englishRecord,
          builder: (_, _) => const Scaffold(body: Text('保存完成')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          englishProgressRepositoryProvider.overrideWith((ref, id) => progress),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('看提示'), findsNothing);
    expect(find.text('提示：红风筝'), findsNothing);
    expect(submitReady(tester), isFalse);
    await tester.runAsync(() => tester.tap(find.text('红风筝')));
    await until(tester, () => submitReady(tester));
    await tester.runAsync(() => tester.tap(find.text('提交答案')));
    await until(tester, () => find.text('完成练习').evaluate().isNotEmpty);
    expect(find.text('red kite'), findsOneWidget);
    expect(find.text('答对了'), findsNothing);
    expect(find.text('完成练习'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('完成练习')));
    await until(tester, () => find.text('保存失败，请重试').evaluate().isNotEmpty);
    expect(progress.load().attempts, isEmpty);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SnackBar), const Offset(0, 100));
    await tester.pumpAndSettle();
    final drafts = PracticeDraftRepository();
    final scope = '${book.pdfSha256}/unit-1-p2/meaning/false/false/$targetKey';
    final sessionId = drafts.get('englishPractice', scope: scope)!['sessionId'];
    router.go('/missing');
    await tester.pumpAndSettle();
    router.go(practicePath);
    await tester.pumpAndSettle();
    expect(find.text('red kite'), findsOneWidget);
    expect(find.text('已安排复习'), findsNothing);
    expect(find.text('完成练习'), findsOneWidget);
    expect(find.text('提交答案'), findsNothing);
    await tester.runAsync(() => tester.tap(find.text('完成练习')));
    await until(tester, () => find.text('保存完成').evaluate().isNotEmpty);
    final attempt = progress.load().attempts.single;
    expect(attempt.id, sessionId);
    expect(attempt.answers.single.question.target.id, 'word-1');
    expect(attempt.answers.single.hinted, isTrue);
    expect(attempt.answers.single.objectiveCorrect, isFalse);
    expect(HiveBoxes.learningActivities.values.single.totalItems, 1);
    expect(HiveBoxes.learningActivities.values.single.successfulItems, 0);
    expect(drafts.get('englishPractice', scope: scope), isNull);
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });
  testWidgets('词义选择跳过保留题面并写入跳过证据，下一题不沿用选中项', (tester) async {
    final book = englishBook();
    await show(
      tester,
      EnglishPracticePage(bookId: book.pdfSha256, kind: 'meaning'),
    );
    expect(submitReady(tester), isFalse);
    await tester.runAsync(() => tester.tap(find.text('跳过')));
    await until(tester, () => find.text('继续练习').evaluate().isNotEmpty);
    expect(find.text('这题已跳过'), findsNothing);
    expect(find.text('red kite'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    final draft = PracticeDraftRepository().get(
      'englishPractice',
      scope: '${book.pdfSha256}/all/meaning/false/false/all',
    )!;
    final answer = EnglishAnswer.fromJson(
      (draft['answers'] as List<dynamic>).single,
    );
    expect(answer.skipped, isTrue);
    expect(answer.correct, isNull);
    expect(answer.objectiveCorrect, isFalse);
    expect(HiveBoxes.learningActivities.values, isEmpty);
    await tester.runAsync(() => tester.tap(find.byTooltip('下一题')));
    await until(tester, () => find.text('blue bird').evaluate().isNotEmpty);
    expect(find.text('blue bird'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    expect(submitReady(tester), isFalse);
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
          (page: const EnglishTabPage(), text: '课本(1)'),
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
            page: EnglishLessonPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              sourceContent: true,
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
            page: EnglishStudyPage(
              bookId: book.pdfSha256,
              lessonId: lesson.id,
              kind: 'vocabulary',
              targetId: 'word-1',
            ),
            text: '单词详情',
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
