import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';
import 'package:poemath/domain/textbook_narration.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_lesson_content_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/textbook_course_fixture.dart';

void main() {
  late NarrationSynth synth;
  late TtsService tts;
  late List<RecordingNarrationPlayer> players;
  setUp(() {
    synth = NarrationSynth();
    players = [];
    tts = TtsService(
      NarrationSettings(),
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final player = RecordingNarrationPlayer();
        players.add(player);
        return player;
      },
    );
  });
  tearDown(() => tts.dispose());

  Future<void> pump(WidgetTester tester,
      {Map<String, dynamic>? raw,
      RouteObserver<ModalRoute<dynamic>>? observer,}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          textbookFileServiceProvider.overrideWithValue(
              TextbookFileService(narrationAudioCache: MemoryNarrationCache()),),
          textbookCourseProvider(courseFixtureHash).overrideWith(
              (_) async => TextbookCoursePack.fromJson(raw ?? courseFixture()),),
        ],
        child: MaterialApp(
          navigatorObservers: [if (observer != null) observer],
          home: TextbookLessonContentPage(
            bookId: courseFixtureHash,
            section: TextbookContentSection.reading,
            pages: const [2],
            routeObserver: observer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    await flushNarration();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('缩进及标点空白清理不改变原文高亮和拼音坐标', (tester) async {
    final raw = courseFixture(); final lesson = (raw['lessons'] as List).single as Map;
    const original = '　　甲， \t乙。\n𠀀 A, B！';
    lesson['paragraphs'] = [courseFixtureText('mapped', original, ['jiǎ', '，', 'yǐ', '。', 'hē', 'ei', ',', 'bi', '！'])];
    lesson['recitations'] = <Object>[]; (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
    final paragraph = TextbookCoursePack.fromJson(raw).lessons.single.paragraphs.single;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextbookCourseText(node: paragraph,
      activeRanges: const [TextbookNarrationSpan('mapped', 6, 10)],),),),);
    for (final index in [6, 7, 9]) {
      expect(tester.widget<Text>(find.byKey(ValueKey('narration-character-mapped-$index'))).style!.backgroundColor, isNotNull);
    }
    for (final index in [2, 11, 14]) {
      expect(tester.widget<Text>(find.byKey(ValueKey('narration-character-mapped-$index'))).style!.backgroundColor, isNull);
    }
    expect(find.text('yǐ'), findsOneWidget); expect(find.text('hē'), findsOneWidget);
    expect(paragraph.text, original); await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同一路由切换页参数和应用后台均停止，不恢复旧朗读', (tester) async {
    final router = createAppRouter(initialLocation: AppRoutes.textbookContentOf(courseFixtureHash, 'reading', [2]));
    await tester.pumpWidget(ProviderScope(overrides: [
      ttsServiceProvider.overrideWithValue(tts),
      textbookFileServiceProvider.overrideWithValue(TextbookFileService(narrationAudioCache: MemoryNarrationCache())),
      textbookCourseProvider(courseFixtureHash).overrideWith((_) async => TextbookCoursePack.fromJson(courseFixture())),
    ], child: MaterialApp.router(routerConfig: router),),);
    await tester.pumpAndSettle(); await tester.tap(find.byTooltip('朗读课文')); await flush(tester);
    players.last.starts.single(); await flush(tester);
    router.go(AppRoutes.textbookContentOf(courseFixtureHash, 'reading', [3]));
    await tester.pumpAndSettle(); expect(players.last.disposed, true);
    expect(find.byTooltip('朗读课文'), findsOneWidget);
    await tester.tap(find.byTooltip('朗读课文')); await flush(tester); players.last.starts.single(); await flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await flush(tester);
    expect(players.last.disposed, true); expect(find.byTooltip('朗读课文'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await flush(tester);
    expect(find.byTooltip('朗读课文'), findsOneWidget); await tester.pumpWidget(const SizedBox()); router.dispose();
  });

  testWidgets('实际播放才高亮，拼音保留且不参与合成，暂停恢复复用同段', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('朗读课文'));
    await flush(tester);
    final content = find.byType(TextbookCourseParagraphsContent);
    expect(tester.widget<TextbookCourseParagraphsContent>(content).activeRanges,
        isEmpty,);
    expect(synth.texts, ['星𠀀，月。']);
    expect(find.text('xīng'), findsOneWidget);
    players.single.starts.single();
    await flush(tester);
    expect(tester.widget<TextbookCourseParagraphsContent>(content).activeRanges,
        isNotEmpty,);
    expect(
        tester.widget<Text>(find.text('星')).style!.backgroundColor, isNotNull,);
    await tester.tap(find.byTooltip('暂停朗读'));
    await flush(tester);
    expect(find.text('已暂停'), findsOneWidget);
    expect(players.single.pauses, 1);
    expect(tester.widget<TextbookCourseParagraphsContent>(content).activeRanges,
        isNotEmpty,);
    await tester.tap(find.byTooltip('继续朗读'));
    await flush(tester);
    expect(players.single.resumes, 1);
    expect(players.single.audio.length, 1);
    expect(synth.texts.length, 1);
    players.single.ends.single.complete();
    await flush(tester);
    expect(find.byTooltip('朗读课文'), findsOneWidget);
    expect(tester.widget<TextbookCourseParagraphsContent>(content).activeRanges,
        isEmpty,);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('生成中离开立即取消，晚到结果不出声；覆盖路由停止且返回不续播', (tester) async {
    final gate = Completer<Uint8List>();
    synth.generate = (_) => gate.future;
    await pump(tester);
    await tester.tap(find.byTooltip('朗读课文'));
    await flush(tester);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    expect(players.single.disposed, true);
    gate.complete(Uint8List(16));
    await flush(tester);
    expect(players.single.audio, isEmpty);
    synth.generate = null;
    players.clear();
    final observer = RouteObserver<ModalRoute<dynamic>>();
    await pump(tester, observer: observer);
    await tester.tap(find.byTooltip('朗读课文'));
    await flush(tester);
    players.single.starts.single();
    await flush(tester);
    final context = tester.element(find.byType(TextbookLessonContentPage));
    unawaited(Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('覆盖页'))),),);
    await tester.pumpAndSettle();
    expect(players.single.disposed, true);
    Navigator.of(tester.element(find.text('覆盖页'))).pop();
    await tester.pumpAndSettle();
    expect(find.byTooltip('朗读课文'), findsOneWidget);
    expect(players.single.audio.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('后课尚未懒构建时按序朗读并滚动到当前正文', (tester) async {
    final raw = courseFixture();
    final lessons = raw['lessons'] as List;
    final first = lessons.single as Map;
    first['paragraphs'] = [
      courseFixtureText(
          'long-paragraph', '${List.filled(80, '星星星星星').join('\n')}。', null,),
    ];
    first['recitations'] = <Object>[];
    (first['coverage'] as Map)['recitations'] = 'notApplicable';
    final second = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
    second['id'] = 'lesson-002';
    second['title'] = '第二课';
    second['lessonNumber'] = 2;
    second['paragraphs'] = [
      courseFixtureText(
          'second-paragraph', '月𠀀明亮。', ['yuè', 'hē', 'míng', 'liàng', '。'],),
    ];
    for (final category
        in TextbookCoursePack.categories.where((c) => c != 'paragraphs')) {
      second[category] = <Object>[];
      (second['coverage'] as Map)[category] = 'notApplicable';
    }
    lessons.add(second);
    ((raw['units'] as List).single as Map)['lessonIds'] = [
      'lesson-001',
      'lesson-002',
    ];
    await pump(tester, raw: raw);
    expect(find.text('第二课'), findsNothing);
    await tester.tap(find.byTooltip('朗读课文'));
    await flush(tester);
    players.single.starts[0]();
    await flush(tester);
    expect(synth.texts.length, 2);
    players.single.ends[0].complete();
    await flush(tester);
    players.single.starts[1]();
    for (var i = 0; i < 50 && find.text('第二课').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('第二课'), findsOneWidget);
    // ensureVisible 滚动动画需要时间完成；长段落合并后滚动距离更长。
    for (var i = 0;
        i < 30 && !tester
            .getRect(find.text('月'))
            .overlaps(tester.getRect(find.byType(Scaffold)));
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final current = tester
        .widgetList<TextbookCourseParagraphsContent>(
            find.byType(TextbookCourseParagraphsContent),)
        .where((c) => c.activeRanges.isNotEmpty)
        .single;
    expect(current.paragraphs.single.id, 'second-paragraph');
    expect(
        tester
            .getRect(find.text('月'))
            .overlaps(tester.getRect(find.byType(Scaffold))),
        true,);
    await tester.pumpWidget(const SizedBox());
  });
}
