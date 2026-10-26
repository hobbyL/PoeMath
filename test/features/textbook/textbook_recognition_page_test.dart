import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          textbookListProvider.overrideWithValue([courseFixtureBook()]),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
          textbookRecognitionBoxProvider.overrideWithValue(box),
          textbookFileServiceProvider.overrideWithValue(
            TextbookFileService(narrationAudioCache: audioCache),
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [if (observer != null) observer],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final all = find.text(text);
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

  Future<void> seed(
    RecognitionQuestionKind kind, {
    bool confirmed = false,
  }) async {
    final r = repo();
    final p = await r.load();
    final lesson = courses.current.lessons.single;
    final targets = recognitionTargets(courses.current, lesson);
    final t = targets.first, c = t.cues.first;
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
    );
    await r.change(
      lessonId: lesson.id,
      fingerprint: s.fingerprint,
      operationId: 'seed',
      expectedRevision: p.revision,
      reduce: (latest, _) => latest.copy(session: s, audio: audio),
    );
  }

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
        recognitionTargets(courses.current, courses.current.lessons.single)
            .where((t) => t.ready)
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
      await tap(tester, '看拼音提示');
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
      await tap(tester, '查看拼音提示');
      await tap(tester, '还需要练习');
      expect(find.text('这次抽查完成了'), findsOneWidget);
      expect((await repo().load()).records.values.single.parentPassed, false);
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
      expect(
        find
            .byKey(const ValueKey('recognition-card-recognition-001'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(IconButton), findsNothing);
      expect(find.text('开始学习'), findsNothing);
      expect(find.text('继续学习'), findsNothing);
      expect(find.text('复习一下'), findsNothing);
      expect(find.text('家长准备'), findsNothing);
      expect(find.text('家长抽查'), findsNothing);
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
    const sentence = '这里有一群小蝌蚪，𠀀的大大的脑袋，黑\n灰色的身子，拖着长长的尾巴。';
    paragraph['text'] = sentence;
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
    await tap(tester, '还要练一练');
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
    await tap(tester, '看拼音提示');
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
  testWidgets('短示范可暂停继续，正文不含拼音；后台停止且自评不确认认读', (tester) async {
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
    await tap(tester, '对照示范，我读对了');
    final p = await repo().load();
    expect(p.records.values.single.selfCorrect, 1);
    expect(p.records.values.single.correct, 0);
    expect(p.records.values.single.parentPassed, isNull);
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
      recognitionTargets(courses.current, courses.current.lessons.single)
          .where((t) => t.ready)
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
