import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/english_recording_store.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/features/english/english_course_page.dart';
import 'package:poemath/features/english/english_practice_page.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_study_page.dart';
import 'package:poemath/features/english/english_target_editor.dart';
import 'package:poemath/features/english/english_widgets.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/english_fixture.dart';
import '../../helpers/english_phrase_fixture.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/parent_access_test_helper.dart';

class _Courses extends EnglishCourseRepository {
  EnglishCourse course = phraseCourse();
  @override
  Future<EnglishCourse?> load(Textbook book) async => course;
  @override
  Future<T> withCurrent<T>(
    Textbook book,
    Future<T> Function(EnglishCourse?) action,
  ) => action(course);
  @override
  Future<EnglishCourse> appendPhrases(
    Textbook book, {
    required String lessonId,
    required int expectedRevision,
    required List<EnglishTarget> phrases,
    required void Function() check,
  }) async {
    check();
    if (course.revision != expectedRevision) {
      throw const FormatException('conflict');
    }
    course = course.change({
      'schemaVersion': 2,
      'revision': course.revision + 1,
      'lessons': [
        course.lessons.single.change({
          'targets': [
            ...course.lessons.single.targets,
            ...phrases,
          ].map((t) => t.toJson()).toList(),
        }).toJson(),
      ],
    });
    return course;
  }
}

void main() {
  late _Courses courses;
  late NarrationSynth synth;
  late TtsService tts;
  late MemoryNarrationCache cache;
  var played = 0;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    courses = _Courses();
    synth = NarrationSynth();
    cache = MemoryNarrationCache();
    played = 0;
    tts = TtsService(
      NarrationSettings(),
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        played++;
        return RecordingNarrationPlayer()..automatic = true;
      },
    );
  });
  tearDown(() async {
    tts.dispose();
    lockParentForTesting();
    await tearDownHiveForWidgetTesting();
  });
  List<Override> overrides({MockClient? client}) => [
    textbookListProvider.overrideWith((ref) => [englishBook()]),
    englishCourseRepositoryProvider.overrideWithValue(courses),
    englishVoiceProvider.overrideWith(
      (ref) => {'locale': 'en-US', 'name': 'test'},
    ),
    englishAudioProvider.overrideWith(
      (ref, key) => EnglishAudio(
        bookId: key.$1,
        tts: tts,
        cache: cache,
        store: EnglishRecordingStore(),
      ),
    ),
    englishTargetCardNumberProvider.overrideWith((ref, key) async => {}),
    englishReviewPageImageBuilderProvider.overrideWithValue(
      (book, page) =>
          SizedBox(key: ValueKey('original-page-$page'), height: 80),
    ),
    if (client != null) llmExplainHttpClientProvider.overrideWithValue(client),
  ];
  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  testWidgets('从课时词表生成、直接朗读与详情练习；同短语播放复用缓存', (tester) async {
    await tester.runAsync(
      () => SettingsRepository().saveLlmProviderConfig(
        id: 'phrase-test',
        name: 'test',
        baseUrl: 'https://test.example.com/v1',
        model: 'model',
        apiKey: '',
      ),
    );
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(
        phraseChatResponse(phraseResponse()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final book = englishBook(), lesson = courses.course.lessons.single;
    final router = GoRouter(
      initialLocation: '/words',
      routes: [
        GoRoute(
          path: '/words',
          builder: (_, state) => EnglishStudyPage(
            bookId: book.pdfSha256,
            lessonId: lesson.id,
            kind: 'vocabulary',
          ),
        ),
        GoRoute(
          path: AppRoutes.englishVocabulary,
          builder: (_, state) => EnglishStudyPage(
            bookId: book.pdfSha256,
            lessonId: lesson.id,
            kind: 'vocabulary',
            targetId: state.pathParameters['target'],
          ),
        ),
        GoRoute(
          path: AppRoutes.englishPractice,
          builder: (_, state) => EnglishPracticePage(
            bookId: book.pdfSha256,
            lessonId: lesson.id,
            kind: state.pathParameters['kind']!,
            targetKey: state.uri.queryParameters['targetKey'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(client: client),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('生成短语'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('生成短语')));
    await until(tester, () => find.text('my father').evaluate().isNotEmpty);
    expect(requests, 1);
    expect(find.text('拓展短语'), findsOneWidget);
    expect(find.text('我的爸爸\nfather · 拓展'), findsOneWidget);
    await tester.ensureVisible(find.text('my father'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('my father')));
    await until(tester, () => find.text('短语详情').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('短语详情'), findsOneWidget);
    expect(find.text('father · 拓展短语'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EnglishStudyPage).last),
      );
      final audio = container.read(
        englishAudioProvider(englishAudioKey(book.pdfSha256)),
      );
      await tester.runAsync(
        () => tester.tap(
          find.byKey(const ValueKey('english-vocabulary-detail-card')),
        ),
      );
      await until(tester, () => !audio.busy && played == i + 1);
    }
    expect(synth.texts, ['my father']);
    await tester.runAsync(() => tester.tap(find.text('词义选择')));
    await until(
      tester,
      () => find.byType(EnglishPracticePage).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).title,
      isA<Text>().having((t) => t.data, 'word', 'my father'),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '提交答案'))
          .onPressed,
      isNull,
    );
    router.pop();
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('拼写练习')));
    await until(
      tester,
      () => find.byType(EnglishPracticePage).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).title,
      isA<Text>().having((t) => t.data, 'meaning', '我的爸爸'),
    );
    expect(find.text('提交答案'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drainHiveWritesForTesting(tester);
  });

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('拓展词表与详情 ${subject.name} ${brightness.name} 适配窄屏横屏大字号', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        courses.course = withPhrases(courses.course);
        final book = englishBook(), lesson = courses.course.lessons.single;
        final phrase = lesson.phrases.first;
        for (final layout in [
          (size: const Size(390, 844), scale: 1.0),
          (size: const Size(320, 740), scale: 2.0),
          (size: const Size(844, 390), scale: 2.0),
        ]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = layout.size;
          for (final detail in [false, true]) {
            await tester.pumpWidget(
              ProviderScope(
                overrides: overrides(),
                child: MaterialApp(
                  theme: AppTheme.resolve(
                    subject: subject,
                    brightness: brightness,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: child!,
                  ),
                  home: EnglishStudyPage(
                    bookId: book.pdfSha256,
                    lessonId: lesson.id,
                    kind: 'vocabulary',
                    targetId: detail ? phrase.id : null,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text(detail ? '短语详情' : '单词与短语'), findsOneWidget);
            if (detail) {
              expect(
                find
                    .byKey(const ValueKey('english-vocabulary-playback'))
                    .hitTestable(),
                findsOneWidget,
              );
              await tester.ensureVisible(find.text('拼写练习'));
            } else {
              await tester.ensureVisible(find.text('补齐短语'));
              await tester.pumpAndSettle();
              expect(find.text('补齐短语').hitTestable(), findsOneWidget);
              await tester.ensureVisible(find.text('a kind father'));
              await tester.pumpAndSettle();
              expect(find.text('a kind father').hitTestable(), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }
        }
        await drainHiveWritesForTesting(tester);
      });
    }
  }

  testWidgets('拓展不会被当作原书图文，编辑直达不会读取空来源', (tester) async {
    courses.course = withPhrases(courses.course);
    final book = englishBook(), lesson = courses.course.lessons.single;
    for (final page in <Widget>[
      EnglishLessonPage(
        bookId: book.pdfSha256,
        lessonId: lesson.id,
        review: true,
      ),
      EnglishTargetEditor(
        bookId: book.pdfSha256,
        lessonId: lesson.id,
        targetId: lesson.phrases.first.id,
      ),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(home: page),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('my father'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await drainHiveWritesForTesting(tester);
  });
}
