import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/tts/narration_audio_identity.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_recognition_repository.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';
import 'package:poemath/features/textbook/textbook_lesson_content_page.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/recognition/recognition_providers.dart';
import 'package:poemath/features/textbook/recognition/textbook_recognition_overview.dart';
import 'package:poemath/features/textbook/recognition/textbook_recognition_practice_page.dart';
import 'package:poemath/features/textbook/recognition/textbook_recognition_prepare_page.dart';
import 'package:poemath/features/textbook/recognition/textbook_recognition_check_page.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/recognition_fixture.dart';
import '../../helpers/textbook_course_fixture.dart';

class MemoryBox extends Fake implements Box<dynamic> {
  final data = <String, dynamic>{};
  bool fail = false;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) {
      fail = false;
      throw HiveError('disk full');
    }
    data[key as String] = value;
  }
}

class OralSettings extends SettingsRepository {
  bool enabled = true;
  bool hasCredentials = true;
  bool failEntryRead = false;
  int entryReads = 0;
  Completer<SpeechRecognitionSettingsState>? entryRead;
  String secretId = 'id';
  @override
  Future<SpeechRecognitionSettingsState> loadSpeechRecognitionSettings() async {
    entryReads++;
    if (failEntryRead) throw StateError('secure storage unavailable');
    return entryRead?.future ?? super.loadSpeechRecognitionSettings();
  }

  @override
  Future<SpeechRecognitionSettingsSnapshot>
      loadSpeechRecognitionSettingsSnapshot() async =>
          SpeechRecognitionSettingsSnapshot(
            credentials: hasCredentials
                ? TencentAsrCredentials(secretId: secretId, secretKey: 'key')
                : null,
            settings: SpeechRecognitionSettingsState(
              hasCredentials: hasCredentials,
              isVerified: hasCredentials && enabled,
            ),
          );
}

class FakeOralService implements SpeechRecognitionService {
  SpeechRecognitionException? startError;
  Completer<SpeechRecognitionResult>? pending;
  int starts = 0, cancels = 0, stops = 0;
  @override
  bool get isRecording => starts > stops;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> start() async {
    starts++;
    if (startError != null) throw startError!;
  }

  @override
  Future<SpeechRecognitionResult> stop() {
    stops++;
    pending = Completer<SpeechRecognitionResult>();
    return pending!.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> dispose() => cancel();
}

class MemoryCourses extends TextbookCourseRepository {
  MemoryCourses(this.current);
  TextbookCoursePack current;
  bool fail = false;
  @override
  Future<TextbookCoursePack?> load(Textbook book) async => current;
  @override
  Future<T> withCurrentPack<T>(
    Textbook book,
    Future<T> Function(TextbookCoursePack?) action,
  ) =>
      action(current);
  @override
  Future<void> save(
    Textbook book,
    TextbookCoursePack pack, {
    required TextbookCoursePack previous,
    void Function()? authorize,
  }) async {
    authorize?.call();
    if (fail) {
      fail = false;
      throw StateError('保存失败');
    }
    expect(previous.toJson(), current.toJson());
    current = pack;
  }
}

void main() {
  late MemoryCourses courses;
  late MemoryBox box;
  late TtsService tts;
  late NarrationSettings settings;
  late NarrationSynth synth;
  late List<RecordingNarrationPlayer> players;
  late MemoryNarrationCache audioCache;
  late OralSettings oralSettings;
  late FakeOralService oral;
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    // The singleton outlives each widget test's fake clock. Initialize its
    // serialized authorization chain in this setup zone for each fresh box.
    await ParentAccessService.instance.initialize();
    courses = MemoryCourses(recognitionFixture());
    box = MemoryBox();
    settings = NarrationSettings();
    synth = NarrationSynth();
    players = [];
    audioCache = MemoryNarrationCache();
    oralSettings = OralSettings()..enabled = false;
    oral = FakeOralService();
    tts = TtsService(
      settings,
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final p = RecordingNarrationPlayer();
        players.add(p);
        return p;
      },
    );
  });
  tearDown(() async {
    tts.dispose();
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });
  TextbookRecognitionRepository repo() => TextbookRecognitionRepository(
        book: courseFixtureBook(),
        editionId: courses.current.edition.id,
        courses: courses,
        box: box,
      );
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    RouteObserver<ModalRoute<dynamic>>? observer,
    double scale = 1,
    bool disableAnimations = false,
    GoRouter? router,
  }) async {
    Widget scaled(BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          settingsRepositoryProvider.overrideWithValue(oralSettings),
          speechRecognitionServiceFactoryProvider.overrideWithValue(() => oral),
          textbookListProvider.overrideWithValue([courseFixtureBook()]),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
          textbookRecognitionBoxProvider.overrideWithValue(box),
          textbookFileServiceProvider.overrideWithValue(
            TextbookFileService(narrationAudioCache: audioCache),
          ),
        ],
        child: router == null
            ? MaterialApp(
                navigatorObservers: [if (observer != null) observer],
                builder: scaled,
                home: page,
              )
            : MaterialApp.router(routerConfig: router, builder: scaled),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final all = find.byWidgetPredicate(
      (widget) =>
          widget is Text && widget.data == text ||
          widget is Tooltip && widget.message == text,
      description: '文字或图标提示：$text',
    );
    if (all.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        all,
        400,
        scrollable: find.byType(Scrollable).first,
      );
    }
    final f = all.first;
    await tester.ensureVisible(f);
    await tester.pump();
    if (text == '保存核对的内容') {
      // ParentAccessService is process-wide; keep its serialized futures in
      // the real zone instead of retaining a previous test's fake clock.
      await tester.runAsync(() => tester.tap(f));
    } else {
      await tester.tap(f);
    }
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    await flushNarration();
    await tester.pump();
  }

  Future<void> openCard(WidgetTester tester, String targetId) async {
    final entry = find.byKey(ValueKey('recognition-practice-$targetId'));
    if (entry.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        entry,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  Future<void> seed(
    RecognitionQuestionKind kind, {
    bool confirmed = false,
    bool recognitionFirst = false,
    String? targetId,
  }) async {
    final r = repo();
    final p = await r.load();
    final lesson = courses.current.lessons.single;
    final targets = recognitionTargets(courses.current, lesson);
    final t = targetId == null
        ? targets.first
        : targets.firstWhere((t) => t.id == targetId);
    final c = t.cues.first;
    final audio = {
      if (confirmed)
        c.key: RecognitionAudioApproval(
          fingerprint: t.fingerprint,
          cueKey: c.key,
          identity: NarrationAudioIdentity(
            cacheKey: 'a' * 64,
            backend: NarrationBackend.cloud,
            audioSha256: 'b' * 64,
          ),
        ),
    };
    final s = RecognitionSession(
      id: 'fixed',
      lessonId: lesson.id,
      fingerprint: recognitionLessonFingerprint(targets),
      epoch: r.epoch,
      startedAt: DateTime.now().toIso8601String(),
      questions: [
        RecognitionQuestion(
          id: 'q',
          targetId: t.id,
          kind: kind,
          cueKey: kind == RecognitionQuestionKind.listen ? c.key : null,
          options: kind == RecognitionQuestionKind.listen
              ? [t.id, targets[1].id]
              : [],
        ),
      ],
      recognitionFirst: recognitionFirst,
    );
    await r.change(
      lessonId: lesson.id,
      fingerprint: s.fingerprint,
      operationId: 'seed',
      expectedRevision: p.revision,
      reduce: (latest, _) => latest.copy(session: s, audio: audio),
    );
  }

  GoRouter recognitionRouter(RouteObserver<ModalRoute<dynamic>> observer) =>
      GoRouter(
        observers: [observer],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => TextbookLessonContentPage(
              bookId: courseFixtureHash,
              section: TextbookContentSection.recognition,
              pages: const [2],
              routeObserver: observer,
            ),
          ),
          GoRoute(
            path: AppRoutes.speechRecognitionSettings,
            builder: (_, __) => Scaffold(
              appBar: AppBar(title: const Text('语音识别配置页')),
            ),
          ),
          GoRoute(
            path: '/other',
            builder: (_, __) => const Scaffold(body: Text('其他页面')),
          ),
          GoRoute(
            path: AppRoutes.textbookRecognitionPractice,
            builder: (_, state) => TextbookRecognitionPracticePage(
              bookId: state.pathParameters['id']!,
              lessonId: state.pathParameters['lesson']!,
              recognitionFirst: true,
              targetId: state.uri.queryParameters['target'],
              routeObserver: observer,
            ),
          ),
        ],
      );

  testWidgets('每张卡片浮动入口直达所点生字，返回不改变字卡和课程', (tester) async {
    oralSettings.enabled = true;
    courses.current = recognitionFixture(approved: false);
    final before = courses.current.toJson();
    await seed(RecognitionQuestionKind.read, recognitionFirst: true);
    final observer = RouteObserver<ModalRoute<dynamic>>();
    final router = recognitionRouter(observer);
    addTearDown(router.dispose);
    await pump(tester, const SizedBox(), router: router);
    final entry = find.byKey(const ValueKey('recognition-practice-star'));
    expect(
      find.ancestor(of: entry, matching: find.byType(AppBar)),
      findsNothing,
    );
    expect(find.widgetWithText(TextButton, '认字'), findsNothing);
    final card =
        tester.getRect(find.byKey(const ValueKey('recognition-card-star')));
    final button = tester.getRect(entry);
    expect(button.right, lessThanOrEqualTo(card.right));
    expect(button.bottom, lessThanOrEqualTo(card.bottom));
    expect(button.center.dx, greaterThan(card.center.dx));
    expect(button.center.dy, greaterThan(card.center.dy));
    expect(find.text('我来认'), findsNothing);
    expect(find.text('家长核对生字'), findsNothing);
    expect(find.text('家长抽查'), findsNothing);
    expect(find.textContaining('先把提示藏起来'), findsNothing);
    expect(find.textContaining('独立认读通过'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('recognition-character-recognition-001')),
    );
    await flush(tester);
    expect(synth.texts, ['𠀀']);
    await tester.tap(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(TextbookRecognitionPracticePage), findsOneWidget);
    expect(players.single.disposed, true);
    final saved = await repo().load();
    expect(saved.session!.recognitionFirst, true);
    expect(
      saved.session!.questions.map((q) => q.targetId).toList(),
      ['star'],
    );
    expect(saved.session!.question.kind, RecognitionQuestionKind.read);
    expect(find.text('请家长核对生字'), findsNothing);
    expect(find.text('xīng'), findsNothing);
    expect(find.text('星'), findsOneWidget);
    expect(synth.texts, ['𠀀']);
    expect(courses.current.toJson(), before);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('认一认·星月测试'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recognition-practice-star')),
      findsOneWidget,
    );
    expect(find.text('xīng'), findsOneWidget);
    expect((await repo().load()).records, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同页多课从各自字卡进入，大字下不混用别课生字', (tester) async {
    oralSettings.enabled = true;
    final raw = recognitionFixture(approved: false).toJson();
    final first = (raw['lessons'] as List).single as Map<String, dynamic>;
    (raw['lessons'] as List).add({
      ...first,
      'id': 'lesson-002',
      'title': '白云测试',
      'lessonNumber': 2,
      'coverage': {
        for (final category in TextbookCoursePack.categories)
          category: category == 'recognitionCharacters'
              ? 'complete'
              : 'notApplicable',
      },
      for (final category in TextbookCoursePack.categories)
        category: <Object?>[],
      'recognitionCharacters': [
        {
          ...courseFixtureText('cloud', '云', ['yún']),
          'requirement': 'recognition',
        },
      ],
    });
    (((raw['units'] as List).single as Map)['lessonIds'] as List)
        .add('lesson-002');
    courses.current = TextbookCoursePack.fromJson(raw);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final router = recognitionRouter(RouteObserver<ModalRoute<dynamic>>());
    addTearDown(router.dispose);
    await pump(tester, const SizedBox(), router: router, scale: 2);
    await openCard(tester, 'cloud');
    final session = (await repo().load()).session!;
    expect(session.lessonId, 'lesson-002');
    expect(session.questions.map((q) => q.targetId).toList(), ['cloud']);
    expect(find.text('云'), findsOneWidget);
    expect(find.text('yún'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('生产路由传入生字，切换卡片与再次练习均保留累计记录', (tester) async {
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookContentOf(
        courseFixtureHash,
        TextbookContentSection.recognition.name,
        [2],
      ),
    );
    addTearDown(router.dispose);
    await pump(tester, const SizedBox(), router: router);
    await openCard(tester, 'star');
    expect(
      GoRouterState.of(
        tester.element(find.byType(TextbookRecognitionPracticePage)),
      ).uri.queryParameters['target'],
      'star',
    );
    await tap(tester, '听示范');
    final hintedId = (await repo().load()).session!.id;
    router.pop();
    await tester.pumpAndSettle();
    await openCard(tester, 'star');
    expect((await repo().load()).session!.id, hintedId);
    expect((await repo().load()).session!.hinted, true);
    router.pop();
    await tester.pumpAndSettle();
    await openCard(tester, 'moon');
    expect(find.text('月'), findsOneWidget);
    expect(find.text('星'), findsNothing);
    expect((await repo().load()).session!.questions.single.targetId, 'moon');
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.complete(const SpeechRecognitionResult(text: '月'));
    await tester.pumpAndSettle();
    expect((await repo().load()).records.values.single.oralCorrect, 1);
    await tap(tester, '看看这一轮');
    await tap(tester, '回到本课');
    await openCard(tester, 'moon');
    expect(find.text('月'), findsOneWidget);
    expect(find.text('读一读'), findsOneWidget);
    expect((await repo().load()).session!.feedback, isNull);
    expect((await repo().load()).records.values.single.oralCorrect, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('失效生字参数不回退到第一字或改写旧轮次', (tester) async {
    await seed(RecognitionQuestionKind.read, recognitionFirst: true);
    final previous = (await repo().load()).toJson();
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        targetId: 'unknown',
      ),
    );
    expect(find.text('找不到这个生字，请返回认一认重试'), findsOneWidget);
    expect(find.text('读一读'), findsNothing);
    expect(find.text('𠀀'), findsNothing);
    expect((await repo().load()).toJson(), previous);
    expect(oral.starts, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320dp大字号的有词句及无词句字卡入口浮在右下角且不误播', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final selected = <String>[];
    await pump(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextbookRecognitionOverview(
              bookId: courseFixtureHash,
              lesson: courses.current.lessons.single,
              onRecognize: selected.add,
            ),
          ],
        ),
      ),
      scale: 2,
    );
    for (final id in ['star', 'go']) {
      final cardFinder = find.byKey(ValueKey('recognition-card-$id'));
      final entry = find.byKey(ValueKey('recognition-practice-$id'));
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      final card = tester.getRect(cardFinder);
      final button = tester.getRect(entry);
      expect(button.right, closeTo(card.right, 0.01));
      expect(button.bottom, closeTo(card.bottom, 0.01));
      expect(button.height, greaterThanOrEqualTo(44));
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }
    expect(selected, ['star', 'go']);
    expect(synth.texts, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final verified in [false, true]) {
    testWidgets('密钥已保存${verified ? '已验证' : '未验证'}时可进入认字并主动录音完成认读',
        (tester) async {
      oralSettings.enabled = verified;
      await seed(
        RecognitionQuestionKind.read,
        recognitionFirst: true,
        targetId: 'star',
      );
      final router = recognitionRouter(RouteObserver<ModalRoute<dynamic>>());
      addTearDown(router.dispose);
      await pump(tester, const SizedBox(), router: router);
      await openCard(tester, 'star');
      expect(find.byType(TextbookRecognitionPracticePage), findsOneWidget);
      expect(find.text('语音识别配置页'), findsNothing);
      expect(oral.starts, 0);
      await tap(tester, '读一读');
      expect(oral.starts, 1);
      await tap(tester, '读完了，听听结果');
      oral.pending!.complete(const SpeechRecognitionResult(text: '星'));
      await tester.pumpAndSettle();
      expect((await repo().load()).records.values.single.oralCorrect, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('未配置密钥进入设置，返回后保存密钥即可进入认字', (tester) async {
    oralSettings.hasCredentials = false;
    final router = recognitionRouter(RouteObserver<ModalRoute<dynamic>>());
    addTearDown(router.dispose);
    await pump(tester, const SizedBox(), router: router);
    await openCard(tester, 'star');
    expect(find.text('语音识别配置页'), findsOneWidget);
    expect(find.byType(TextbookRecognitionPracticePage), findsNothing);
    expect((await repo().load()).session, isNull);
    expect(oral.starts, 0);
    oralSettings.hasCredentials = true;
    router.pop();
    await tester.pumpAndSettle();
    await openCard(tester, 'star');
    expect(find.byType(TextbookRecognitionPracticePage), findsOneWidget);
    expect(find.text('读一读'), findsOneWidget);
    expect(oral.starts, 0);
    expect(oralSettings.entryReads, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('未验证密钥被云端拒绝时显示原因，不记录认读对错并可重录', (tester) async {
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.completeError(
      const TencentAsrException(
        '腾讯云密钥无效或没有识别权限',
        kind: TencentAsrErrorKind.authentication,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('腾讯云密钥无效或没有识别权限'), findsOneWidget);
    expect((await repo().load()).records, isEmpty);
    await tap(tester, '读一读');
    expect(oral.starts, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('读取认字配置期间防重复点击，离开页面后不产生迟到跳转', (tester) async {
    oralSettings.entryRead = Completer<SpeechRecognitionSettingsState>();
    final router = recognitionRouter(RouteObserver<ModalRoute<dynamic>>());
    addTearDown(router.dispose);
    await pump(tester, const SizedBox(), router: router);
    final entry = find.byKey(const ValueKey('recognition-practice-star'));
    await tester.tap(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(oralSettings.entryReads, 1);
    unawaited(router.push<void>('/other'));
    await tester.pumpAndSettle();
    oralSettings.entryRead!.complete(
      const SpeechRecognitionSettingsState(
        hasCredentials: true,
        isVerified: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('其他页面'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('认一认·星月测试'), findsOneWidget);
    expect((await repo().load()).session, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('读取认字配置失败可重试，不创建练习轮次', (tester) async {
    oralSettings.hasCredentials = false;
    oralSettings.failEntryRead = true;
    final router = recognitionRouter(RouteObserver<ModalRoute<dynamic>>());
    addTearDown(router.dispose);
    await pump(tester, const SizedBox(), router: router);
    await openCard(tester, 'star');
    expect(find.text('无法读取语音识别配置，请重试'), findsOneWidget);
    expect((await repo().load()).session, isNull);
    oralSettings.failEntryRead = false;
    await openCard(tester, 'star');
    expect(find.text('语音识别配置页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('认字字卡上移缩小，语音图标置于卡片外侧右边，小屏大字仍可操作', (tester) async {
    oralSettings.enabled = true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await seed(RecognitionQuestionKind.read, targetId: 'star');
    final page = TextbookRecognitionPracticePage(
      bookId: courseFixtureHash,
      lessonId: 'lesson-001',
    );
    for (final scale in [1.0, 2.0]) {
      await pump(tester, page, scale: scale);
      expect(find.textContaining('步 ·'), findsNothing);
      expect(find.text('这个字你认识吗？自己读出来'), findsNothing);
      expect(find.textContaining('可以先自己'), findsNothing);
      expect(find.text('设置语音识别'), findsNothing);
      expect(find.text('看拼音提示'), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('对照示范，我读对了'), findsNothing);
      expect(find.text('还要练一练'), findsNothing);
      expect(find.text('听说明'), findsNothing);
      expect(find.text('听示范'), findsNothing);
      expect(find.textContaining('点麦克风后'), findsNothing);
      final card = tester.getRect(
        find.byKey(const ValueKey('recognition-practice-character-card')),
      );
      expect(card.width, lessThan(240));
      expect(card.center.dx, closeTo(160, 0.1));
      expect(card.top, lessThan(kToolbarHeight));
      if (scale == 1) {
        expect(card.width, lessThan(192));
        expect(card.height, lessThan(192));
      }
      final explanation = tester.getRect(find.byTooltip('听说明'));
      final demonstration = tester.getRect(find.byTooltip('听示范'));
      expect(explanation.center.dx, closeTo(demonstration.center.dx, 0.1));
      expect(explanation.bottom, lessThanOrEqualTo(demonstration.top));
      expect(explanation.top, greaterThanOrEqualTo(card.top));
      expect(explanation.left, greaterThan(card.right));
      expect(demonstration.left, greaterThan(card.right));
      expect(demonstration.right, lessThanOrEqualTo(320));
      expect(explanation.width, greaterThanOrEqualTo(44));
      expect(explanation.height, greaterThanOrEqualTo(44));
      expect(
        tester.getCenter(find.byType(BackButton)),
        const Offset(kToolbarHeight / 2, kToolbarHeight / 2),
      );
      final character = tester.widget<Text>(find.text('星'));
      final theme = Theme.of(tester.element(find.text('星')));
      expect(character.style?.fontSize, theme.textTheme.displayLarge?.fontSize);
      expect(tester.takeException(), isNull);
    }
    await tap(tester, '听示范');
    await flush(tester);
    expect((await repo().load()).session!.hinted, true);
    expect(find.text('xīng'), findsOneWidget);
    expect(find.textContaining('已用过提示'), findsNothing);
    expect(
      tester.getTopLeft(find.text('xīng')).dy,
      lessThan(tester.getTopLeft(find.text('星')).dy),
    );
    final back = tester.getRect(find.byType(BackButton));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(BackButton)), back);
    expect(find.byType(BackButton).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('未审核字卡直接复用ASR和回退拼音，不写课程审批', (tester) async {
    final raw = recognitionFixture(approved: false).toJson();
    final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
    final star = (lesson['recognitionCharacters'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((t) => t['id'] == 'star');
    star['pinyin'] = null;
    lesson['recognitionCharacters'] = [star];
    courses.current = TextbookCoursePack.fromJson(raw);
    final before = courses.current.toJson();
    oralSettings.enabled = true;
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    expect(find.text('星'), findsOneWidget);
    expect(find.text('xīng'), findsNothing);
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.complete(
      const SpeechRecognitionResult(text: '星'),
    );
    await flush(tester);
    expect((await repo().load()).records.values.single.oralCorrect, 1);
    expect(courses.current.toJson(), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('独立录音结果保存失败可重试，先隐藏拼音，提示通过不算独立', (tester) async {
    oralSettings.enabled = true;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    final page = TextbookRecognitionPracticePage(
      bookId: courseFixtureHash,
      lessonId: 'lesson-001',
      recognitionFirst: true,
    );
    await pump(tester, page);
    expect(find.text('xīng'), findsNothing);
    await tap(tester, '读一读');
    expect(oral.starts, 1);
    await tap(tester, '读完了，听听结果');
    box.fail = true;
    oral.pending!.complete(
      const SpeechRecognitionResult(text: '星'),
    );
    await flush(tester);
    expect((await repo().load()).records, isEmpty);
    await tap(tester, '重试');
    expect((await repo().load()).records.values.single.oralCorrect, 1);
    expect(find.text('xīng'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    await pump(tester, page);
    expect((await repo().load()).records.values.single.oralCorrect, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('提示先保存后播放，口语通过仅记提示练习；未听清不记错误', (tester) async {
    oralSettings.enabled = true;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    box.fail = true;
    await tap(tester, '听示范');
    expect(synth.texts, isEmpty);
    expect(
      tester.getTopLeft(find.text('重试')).dy,
      greaterThan(tester.getBottomLeft(find.byType(BackButton)).dy),
    );
    await tap(tester, '重试');
    await flush(tester);
    expect((await repo().load()).session!.hinted, isTrue);
    expect(synth.texts, ['星']);
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.complete(
      const SpeechRecognitionResult(text: ''),
    );
    await flush(tester);
    expect((await repo().load()).records, isEmpty);
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.complete(
      const SpeechRecognitionResult(text: '星'),
    );
    await flush(tester);
    final record = (await repo().load()).records.values.single;
    expect(record.oralCorrect, 0);
    expect(record.hints, 1);
    expect(record.oralAgain, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('后台取消与旧结果不会提交或影响新的录音', (tester) async {
    oralSettings.enabled = true;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    final pending = oral.pending!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    await tap(tester, '读一读');
    pending.complete(
      const SpeechRecognitionResult(text: '星'),
    );
    await flush(tester);
    expect((await repo().load()).records, isEmpty);
    expect(find.text('读完了，听听结果'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets('旧认字路由在无密钥时不录音，不再提供页面内设置入口', (tester) async {
    oralSettings.hasCredentials = false;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    expect(find.text('读一读'), findsNothing);
    expect(find.text('设置语音识别'), findsNothing);
    expect(find.textContaining('可以先自己'), findsNothing);
    expect(find.textContaining('口语评测'), findsNothing);
    expect(oral.starts, 0);
    expect(oral.stops, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ASR同音同调可以通过，识别期间凭据变化不写认读证据', (tester) async {
    oralSettings.enabled = true;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oralSettings.secretId = 'changed';
    oral.pending!.complete(const SpeechRecognitionResult(text: '猩'));
    await flush(tester);
    expect((await repo().load()).records, isEmpty);
    expect(find.text('语音识别配置已变化，这次还没确认'), findsOneWidget);
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.complete(const SpeechRecognitionResult(text: '猩'));
    await flush(tester);
    expect((await repo().load()).records.values.single.oralCorrect, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('多音字初始不显示操作文案，单字不确认后提示组词，错读语境记待练', (tester) async {
    oralSettings.enabled = true;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'go',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    expect(find.textContaining('请自己组个词来读'), findsNothing);
    expect(find.text('xíng'), findsNothing);
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.complete(const SpeechRecognitionResult(text: '行'));
    await flush(tester);
    expect((await repo().load()).records, isEmpty);
    expect(find.text('这次还不能确定读音，请自己组个词再读一次，或换个词试试。'), findsOneWidget);
    await tap(tester, '读一读');
    await tap(tester, '读完了，听听结果');
    oral.pending!.complete(const SpeechRecognitionResult(text: '银行'));
    await flush(tester);
    final record = (await repo().load()).records.values.single;
    expect(record.oralCorrect, 0);
    expect(record.oralAgain, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('十秒自动结束只识别一次，服务失败不记对错且可以重录', (tester) async {
    oralSettings.enabled = true;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    await tap(tester, '读一读');
    await tester.pump(const Duration(seconds: 10));
    await flush(tester);
    expect(oral.stops, 1);
    oral.pending!.completeError(const SpeechRecognitionException('识别网络请求失败'));
    await flush(tester);
    expect((await repo().load()).records, isEmpty);
    expect(find.text('识别网络请求失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(oral.stops, 1);
    await tap(tester, '读一读');
    expect(oral.starts, 2);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    expect((await repo().load()).records, isEmpty);
  });

  testWidgets('麦克风启动失败清理服务并恢复重试入口', (tester) async {
    oralSettings.enabled = true;
    oral.startError = const SpeechPermissionDeniedException();
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    await tap(tester, '读一读');
    expect(oral.starts, 1);
    expect(oral.cancels, 1);
    expect(oral.stops, 0);
    expect(find.text('未获得麦克风权限'), findsOneWidget);
    expect((await repo().load()).records, isEmpty);
    oral.startError = null;
    await tap(tester, '读一读');
    expect(find.text('读完了，听听结果'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets('录音时配置被撤销不上传音频', (tester) async {
    oralSettings.enabled = true;
    await seed(
      RecognitionQuestionKind.read,
      recognitionFirst: true,
      targetId: 'star',
    );
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        recognitionFirst: true,
      ),
    );
    await tap(tester, '读一读');
    oralSettings.hasCredentials = false;
    await tap(tester, '读完了，听听结果');
    expect(oral.stops, 0);
    expect(oral.cancels, 1);
    expect((await repo().load()).records, isEmpty);
    expect(find.text('语音识别配置已变化，请重新进入练习'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final viewport in <Size>[const Size(320, 640), const Size(640, 320)]) {
    testWidgets(
        '小屏/横屏 ${viewport.width}×${viewport.height}：两倍字号和减少动画仍可准备、练习和抽查',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      courses.current = recognitionFixture(approved: false);
      await pump(
        tester,
        TextbookRecognitionPreparePage(
          bookId: courseFixtureHash,
          lessonId: 'lesson-001',
        ),
        scale: 2,
        disableAnimations: true,
      );
      await tap(tester, '已确认课目归属、来源页和本课认字范围');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: find.text('已确认课目归属、来源页和本课认字范围'),
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        true,
      );
      await tap(tester, '已核对这个字、拼音和选定示范');
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .where((tile) => tile.value == true)
            .isNotEmpty,
        true,
      );
      await tap(tester, '保存核对的内容');
      expect(
        courses.current.lessons.single.recognitionCharacters
            .where((t) => t.isApproved)
            .length,
        1,
      );
      expect((await repo().load()).records, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await seed(RecognitionQuestionKind.study);
      await pump(
        tester,
        TextbookRecognitionPracticePage(
          bookId: courseFixtureHash,
          lessonId: 'lesson-001',
        ),
        scale: 2,
        disableAnimations: true,
      );
      expect(find.text('hē'), findsNothing);
      await tap(tester, '听示范');
      await tap(tester, '试过了，开始练习');
      await tap(tester, '看看这一轮');
      expect(find.text('这一轮完成了'), findsOneWidget);
      expect((await repo().load()).records.values.single.studies, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await pump(
        tester,
        TextbookRecognitionCheckPage(
          bookId: courseFixtureHash,
          lessonId: 'lesson-001',
        ),
        scale: 2,
        disableAnimations: true,
      );
      for (var i = 0; i < 5; i++) {
        await tap(tester, '查看拼音提示');
        await tap(tester, '还需要练习');
      }
      expect(find.text('这次抽查完成了'), findsOneWidget);
      final checked = (await repo().load()).records.values.toList();
      expect(checked.length, 5);
      expect(checked.every((r) => r.parentPassed == false), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await pump(
        tester,
        Scaffold(
          body: SafeArea(
            child: ListView(
              children: [
                TextbookRecognitionOverview(
                  bookId: courseFixtureHash,
                  lesson: courses.current.lessons.single,
                ),
              ],
            ),
          ),
        ),
        scale: 2,
        disableAnimations: true,
      );
      expect(
        find.byKey(const ValueKey('recognition-card-recognition-001')),
        findsOneWidget,
      );
      expect(find.text('hē'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('recognition-card-recognition-001')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IconButton), findsNothing);
      expect(find.text('开始学习'), findsNothing);
      expect(find.text('继续学习'), findsNothing);
      expect(find.text('复习一下'), findsNothing);
      expect(find.text('家长准备'), findsNothing);
      expect(find.text('家长抽查'), findsNothing);
      expect(find.text('家长核对生字'), findsNothing);
      expect(find.text('我来认'), findsNothing);
      expect(find.textContaining('先把提示藏起来'), findsNothing);
      expect(find.textContaining('独立认读通过'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('认一认概览分开播放单字和词句并复用已缓存语音', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: SafeArea(
          child: ListView(
            children: [
              TextbookRecognitionOverview(
                bookId: courseFixtureHash,
                lesson: courses.current.lessons.single,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('recognition-card-recognition-001')),
      findsOneWidget,
    );
    expect(find.text('𠀀'), findsOneWidget);
    expect(find.text('hē'), findsOneWidget);
    expect(find.text('星𠀀，月。'), findsOneWidget);
    expect(find.text('课文词句：星𠀀，月'), findsNothing);
    expect(find.byKey(const ValueKey('recognition-masonry')), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('继续学习'), findsNothing);

    final character = find.byKey(
      const ValueKey('recognition-character-recognition-001'),
    );
    final note = find.byKey(
      const ValueKey('recognition-note-recognition-001'),
    );
    final card = find.byKey(
      const ValueKey('recognition-card-recognition-001'),
    );
    final cardRect = tester.getRect(card);
    await tester.tapAt(Offset(cardRect.left + 2, cardRect.top + 24));
    await flush(tester);
    expect(synth.texts, ['𠀀']);

    players.last.starts.single();
    await tester.tap(character);
    await flush(tester);
    expect(players.last.pauses, 1);
    await tester.tap(character);
    await flush(tester);
    expect(players.last.resumes, 1);
    players.last.ends.single.complete();
    await flush(tester);
    await tester.tap(character);
    await flush(tester);
    expect(synth.texts, ['𠀀']);
    expect(players.length, 2);

    await tester.tapAt(Offset(cardRect.right - 2, cardRect.bottom - 24));
    await flush(tester);
    expect(synth.texts, ['𠀀', '星𠀀，月。']);
    expect(players.length, 3);

    final characterRect = tester.getRect(character);
    final noteRect = tester.getRect(note);
    await tester.tapAt(Offset(cardRect.center.dx, characterRect.bottom - 1));
    await flush(tester);
    expect(synth.texts, ['𠀀', '星𠀀，月。']);
    expect(players.length, 4);
    await tester.tapAt(Offset(cardRect.center.dx, noteRect.top + 1));
    await flush(tester);
    expect(synth.texts, ['𠀀', '星𠀀，月。']);
    expect(players.length, 5);

    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    expect(players.last.disposed, true);
  });

  testWidgets('认一认长句完整显示并按实际高度瀑布流排列', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final raw = courses.current.toJson();
    final lessonRaw = (raw['lessons'] as List).single as Map<String, dynamic>;
    final paragraph =
        (lessonRaw['paragraphs'] as List).single as Map<String, dynamic>;
    const source = '这里有一群小蝌蚪，𠀀的大大的脑袋，黑\n灰色的身子，拖着长长的尾巴。';
    const sentence = '这里有一群小蝌蚪，𠀀的大大的脑袋，黑灰色的身子，拖着长长的尾巴。';
    paragraph['text'] = source;
    paragraph['pinyin'] = null;
    final range = ((((lessonRaw['recitations'] as List).single
            as Map<String, dynamic>)['ranges'] as List)
        .single as Map<String, dynamic>);
    range['textSha256'] = textbookTextDigest('这里');
    courses.current = TextbookCoursePack.fromJson(raw);

    await pump(
      tester,
      Scaffold(
        body: SafeArea(
          child: ListView(
            children: [
              TextbookRecognitionOverview(
                bookId: courseFixtureHash,
                lesson: courses.current.lessons.single,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text(sentence), findsOneWidget);
    final first = find.byKey(
      const ValueKey('recognition-card-recognition-001'),
    );
    final second = find.byKey(const ValueKey('recognition-card-star'));
    final third = find.byKey(const ValueKey('recognition-card-moon'));
    final firstTop = tester.getTopLeft(first);
    final secondTop = tester.getTopLeft(second);
    final thirdTop = tester.getTopLeft(third);
    expect(firstTop.dx, lessThan(secondTop.dx));
    expect(thirdTop.dy, lessThan(tester.getBottomLeft(first).dy));
    expect(
      tester.getSize(first).width,
      closeTo(tester.getSize(second).width, 0.01),
    );
    await tester.tap(
      find.byKey(const ValueKey('recognition-note-recognition-001')),
    );
    await flush(tester);
    expect(synth.texts, [sentence]);
  });

  testWidgets('档案切换立即停止；切回同档案也不能使旧页面恢复写入', (tester) async {
    await seed(RecognitionQuestionKind.read);
    final previous = repo();
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
      ),
    );
    await tap(tester, '听示范');
    await flush(tester);
    players.last.starts.single();
    await flush(tester);
    ProfileScope.switchTo('another');
    await flush(tester);
    expect(players.last.disposed, true);
    ProfileScope.reset();
    await flush(tester);
    await expectLater(previous.load(), throwsStateError);
    await tap(tester, '读一读');
    expect(oral.starts, 0);
    expect((await repo().load()).records, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('拼音先隐藏；失败不切题，重试/重新进入不重复记数', (tester) async {
    await seed(RecognitionQuestionKind.study);
    const page = TextbookRecognitionPracticePage(
      bookId:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      lessonId: 'lesson-001',
    );
    await pump(tester, page);
    expect(find.text('hē'), findsNothing);
    await tap(tester, '听示范');
    expect(find.text('hē'), findsOneWidget);
    box.fail = true;
    await tap(tester, '试过了，开始练习');
    expect((await repo().load()).records, isEmpty);
    expect(find.text('重试'), findsOneWidget);
    await tap(tester, '重试');
    expect((await repo().load()).records.values.single.studies, 1);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    await pump(tester, page);
    expect(find.text('下一步'), findsNothing);
    expect(find.text('看看这一轮'), findsOneWidget);
    expect((await repo().load()).records.values.single.studies, 1);
    await tap(tester, '看看这一轮');
    expect(find.text('这一轮完成了'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('短示范图标可暂停继续，合成内容不含拼音；听过不产生认读结果', (tester) async {
    await seed(RecognitionQuestionKind.read);
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
      ),
    );
    await tap(tester, '听示范');
    await flush(tester);
    expect(synth.texts, ['𠀀']);
    players.last.starts.single();
    await flush(tester);
    await tap(tester, '暂停');
    await flush(tester);
    expect(players.last.pauses, 1);
    await tap(tester, '继续播放');
    await flush(tester);
    expect(players.last.resumes, 1);
    players.last.ends.single.complete();
    await flush(tester);
    final p = await repo().load();
    expect(p.session!.hinted, true);
    expect(p.records, isEmpty);
    expect(oral.starts, 0);
    expect(find.text('对照示范，我读对了'), findsNothing);
    expect(find.text('还要练一练'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('听说明不允许答题；音频身份变化在播放前取消，可跳题', (tester) async {
    await seed(RecognitionQuestionKind.listen, confirmed: true);
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
      ),
    );
    await tap(tester, '听说明');
    await flush(tester);
    players.last.starts.single();
    players.last.ends.single.complete();
    await flush(tester);
    final option = find.ancestor(
      of: find.text('𠀀'),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(option).onPressed, isNull);
    await tap(tester, '听题目');
    await flush(tester);
    expect(players.last.audio, isEmpty);
    expect(find.text('先跳过这道听音题'), findsOneWidget);
    await tap(tester, '先跳过这道听音题');
    expect((await repo().load()).records, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('家长准备失败/取消不批准，部分字核对成功且不计孩子学习', (tester) async {
    courses.current = recognitionFixture(approved: false);
    await pump(
      tester,
      TextbookRecognitionPreparePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
      ),
    );
    await tap(tester, '已确认课目归属、来源页和本课认字范围');
    await tap(tester, '已核对这个字、拼音和选定示范');
    courses.fail = true;
    await tap(tester, '保存核对的内容');
    expect(courses.current.lessons.single.isApproved, false);
    await tap(tester, '保存核对的内容');
    expect(
      courses.current.lessons.single.recognitionCharacters
          .where((t) => t.isApproved)
          .length,
      1,
    );
    expect((await repo().load()).records, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('家长抽查查看提示后不标独立认读，下一字确认单独记录', (tester) async {
    await pump(
      tester,
      TextbookRecognitionCheckPage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
      ),
      scale: 2,
    );
    await tap(tester, '查看拼音提示');
    await tap(tester, '孩子独立读对了');
    var p = await repo().load();
    expect(p.records.values.single.parentPassed, isNull);
    expect(p.records.values.single.hints, 1);
    await tap(tester, '孩子独立读对了');
    p = await repo().load();
    expect(p.records.values.where((r) => r.parentPassed == true).length, 1);
    expect(p.records.values.every((r) => r.correct == 0), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('家长完整试听确认后，听音和词句题都有真实完成路径', (tester) async {
    await pump(
      tester,
      TextbookRecognitionPreparePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
      ),
    );
    await tap(tester, '试听示范：𠀀');
    await flush(tester);
    final confirms = find.widgetWithText(TextButton, '完整听过，确认读准');
    expect(
      confirms
          .evaluate()
          .every((e) => (e.widget as TextButton).onPressed == null),
      true,
    );
    players.last.starts.single();
    players.last.ends.single.complete();
    await flush(tester);
    final enabled = confirms
        .evaluate()
        .map((e) => e.widget as TextButton)
        .firstWhere((b) => b.onPressed != null);
    await tester.ensureVisible(find.byWidget(enabled));
    await tester.pump();
    await tester.tap(find.byWidget(enabled));
    await tester.pumpAndSettle();
    final r = repo(), p = await repo().load();
    expect(p.audio.length, 1);
    expect(p.records, isEmpty);
    final lesson = courses.current.lessons.single,
        targets =
            recognitionTargets(courses.current, courses.current.lessons.single);
    final target = targets.first, single = targets.first.cues.first;
    final context = target.cues.firstWhere((c) => c.nodeId != target.id);
    final s = RecognitionSession(
      id: 'mixed',
      lessonId: lesson.id,
      fingerprint: recognitionLessonFingerprint(targets),
      epoch: r.epoch,
      startedAt: DateTime.now().toIso8601String(),
      questions: [
        RecognitionQuestion(
          id: 'listen',
          targetId: target.id,
          kind: RecognitionQuestionKind.listen,
          cueKey: single.key,
          options: [target.id, targets[1].id],
        ),
        RecognitionQuestion(
          id: 'context',
          targetId: target.id,
          kind: RecognitionQuestionKind.context,
          cueKey: single.key,
          options: [context.key],
          positions: context.positions,
        ),
      ],
    );
    await r.change(
      lessonId: lesson.id,
      fingerprint: s.fingerprint,
      operationId: 'mixed',
      expectedRevision: p.revision,
      reduce: (latest, _) => latest.copy(session: s),
    );
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: lesson.id,
      ),
    );
    await tap(tester, '听题目');
    await flush(tester);
    players.last.starts.single();
    players.last.ends.single.complete();
    await flush(tester);
    await tap(tester, '𠀀');
    await tap(tester, '下一步');
    expect(find.text('hē'), findsNothing);
    await tap(tester, '听题目');
    await flush(tester);
    players.last.starts.single();
    players.last.ends.single.complete();
    await flush(tester);
    await tap(tester, '𠀀');
    expect((await repo().load()).records.values.single.correct, 2);
    expect((await repo().load()).records.values.single.parentPassed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('播放中被新路由覆盖及后台均停止，返回保留未提交题', (tester) async {
    await seed(RecognitionQuestionKind.read);
    final observer = RouteObserver<ModalRoute<dynamic>>();
    await pump(
      tester,
      TextbookRecognitionPracticePage(
        bookId: courseFixtureHash,
        lessonId: 'lesson-001',
        routeObserver: observer,
      ),
      observer: observer,
    );
    await tap(tester, '听示范');
    await flush(tester);
    players.last.starts.single();
    await flush(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('覆盖页'))),
      ),
    );
    await tester.pumpAndSettle();
    await flush(tester);
    expect(players.last.disposed, true);
    navigator.pop();
    await tester.pumpAndSettle();
    await tap(tester, '听示范');
    await flush(tester);
    players.last.starts.single();
    await flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await flush(tester);
    expect(players.last.disposed, true);
    expect((await repo().load()).records, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
