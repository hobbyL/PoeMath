import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/textbook_dictation_page.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/writing_fixture.dart';

void main() {
  late TextbookCoursePack? pack;
  late TtsService tts;
  late NarrationSynth synth;
  late MemoryNarrationCache cache;
  late List<RecordingNarrationPlayer> players;
  late ProviderContainer container;
  var automatic = true;
  final book = courseFixtureBook();

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    pack = writingFixture();
    synth = NarrationSynth();
    cache = MemoryNarrationCache();
    players = [];
    automatic = true;
    tts = TtsService(
      NarrationSettings(),
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final player = RecordingNarrationPlayer()..automatic = automatic;
        players.add(player);
        return player;
      },
    );
  });

  tearDown(() async {
    tts.dispose();
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  List<Override> overrides() => [
        ttsServiceProvider.overrideWithValue(tts),
        textbookCourseProvider(book.pdfSha256).overrideWith((_) async => pack),
        textbookFileServiceProvider.overrideWithValue(
          TextbookFileService(narrationAudioCache: cache),
        ),
        writingStrokeDataProvider.overrideWith(
          (_) async => const WritingStrokeAsset({}),
        ),
        textbookWritingProgressProvider(book.pdfSha256)
            .overrideWith((_) async => null),
      ];

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.resolve(
            subject: AppSubject.poem,
            brightness: brightness,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: TextbookDictationPage(
            bookId: book.pdfSha256,
            lessonId: 'lesson-001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(TextbookDictationPage)),
    );
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    // 田字格抢占书写手势；从页边滚动，避免把滚动误记为一笔。
    for (var i = 0; finder.evaluate().isEmpty && i < 30; i++) {
      final viewport = tester.getRect(find.byType(Scrollable).first);
      await tester.dragFrom(
        Offset(viewport.left + 8, viewport.center.dy),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester, {bool handwriting = false}) async {
    if (handwriting) await tapKey(tester, 'dictation-mode-handwriting');
    await tapKey(tester, 'dictation-start');
  }

  testWidgets('纸上听写整轮隐藏答案，播报顺序与最终核对顺序一致', (tester) async {
    await pump(tester);
    expect(find.text('听写·星月测试'), findsOneWidget);
    expect(find.text('星月测试'), findsNothing);
    expect(find.textContaining('本课 2 个会写字'), findsNothing);
    await start(tester);
    expect(find.text('听写·星月测试'), findsOneWidget);
    final first = synth.texts.single;
    expect(first, anyOf('星月，请写第1个字。', '星月，请写第2个字。'));
    expect(find.text('第 1 / 2 题'), findsOneWidget);
    expect(find.text('星'), findsNothing);
    expect(find.text('月'), findsNothing);
    expect(find.text('xīng'), findsNothing);
    expect(find.text(first), findsNothing);
    expect(find.byType(WritingCanvas), findsNothing);
    expect(find.text('整轮核对'), findsNothing);

    await tapKey(tester, 'dictation-next');
    expect(find.text('第 2 / 2 题'), findsOneWidget);
    expect(find.text('星'), findsNothing);
    expect(find.text('月'), findsNothing);
    expect(synth.texts.toSet(), {'星月，请写第1个字。', '星月，请写第2个字。'});

    await tapKey(tester, 'dictation-next');
    expect(find.text('整轮核对'), findsOneWidget);
    expect(find.text('听写·星月测试'), findsOneWidget);
    final expected = first.contains('第1') ? '星' : '月';
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dictation-review-0')),
        matching: find.text(expected),
      ),
      findsOneWidget,
    );
    expect(synth.texts.length, 2);
    expect(players.every((player) => player.disposed), isTrue);
  });

  testWidgets('全部核对后只重听错字，新一轮清除旧标记，全课重来恢复完整范围', (tester) async {
    await pump(tester);
    await start(tester);
    final wrongCharacter = synth.texts.first.contains('第1') ? '星' : '月';
    await tapKey(tester, 'dictation-next');
    await tapKey(tester, 'dictation-next');
    await tapKey(tester, 'dictation-wrong-0');
    await tapKey(tester, 'dictation-correct-1');
    await tapKey(tester, 'dictation-retry-wrong');
    expect(find.text('第 1 / 1 题'), findsOneWidget);
    expect(find.text(wrongCharacter), findsNothing);
    await tapKey(tester, 'dictation-next');
    expect(find.text(wrongCharacter), findsOneWidget);
    expect(find.text('已核对 0 / 1，写对 0 个，还要练 0 个'), findsOneWidget);
    await tapKey(tester, 'dictation-retry-all');
    expect(find.text('第 1 / 2 题'), findsOneWidget);
  });

  testWidgets('屏幕手写无底字，逐题保留笔迹，整轮后并排核对', (tester) async {
    await pump(tester);
    await start(tester, handwriting: true);
    final firstInput = find.byKey(const ValueKey('dictation-input-0'));
    final input = tester.widget<WritingCanvas>(firstInput);
    expect(input.showCharacter, isNull);
    expect(input.referenceStrokes, isNull);
    expect(input.traceOpacity, 0);
    expect(find.text('标准字'), findsNothing);
    await tester.drag(firstInput, const Offset(40, 20));
    await tester.pumpAndSettle();
    final firstStrokes = tester.widget<WritingCanvas>(firstInput).strokes;
    expect(firstStrokes.length, 1);
    await tapKey(tester, 'dictation-next');

    final secondInput = find.byKey(const ValueKey('dictation-input-1'));
    expect(tester.widget<WritingCanvas>(secondInput).strokes, isEmpty);
    await tester.drag(secondInput, const Offset(-30, -60));
    await tester.pumpAndSettle();
    final secondStrokes = tester.widget<WritingCanvas>(secondInput).strokes;
    await tapKey(tester, 'dictation-next');
    expect(find.text('整轮核对'), findsOneWidget);
    final firstPreview = tester.widget<WritingCanvas>(
      find.byKey(const ValueKey('dictation-answer-0')),
    );
    expect(firstPreview.enabled, isFalse);
    expect(firstPreview.strokes, firstStrokes);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dictation-answer-1')),
      200,
    );
    final secondPreview = tester.widget<WritingCanvas>(
      find.byKey(const ValueKey('dictation-answer-1')),
    );
    expect(secondPreview.strokes, secondStrokes);
    expect(secondPreview.strokes, isNot(firstStrokes));
    expect(find.text('标准字'), findsWidgets);
    expect(find.text('我写的'), findsWidgets);
  });

  testWidgets('屏幕手写撤销清空生效，空白作答可跳过且最终提示未作答', (tester) async {
    await pump(tester);
    await start(tester, handwriting: true);
    final input = find.byKey(const ValueKey('dictation-input-0'));
    await tester.drag(input, const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.drag(input, const Offset(-20, -20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销一笔'));
    await tester.pumpAndSettle();
    expect(tester.widget<WritingCanvas>(input).strokes.length, 1);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(tester.widget<WritingCanvas>(input).strokes, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('dictation-next')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'dictation-skip');
    await tapKey(tester, 'dictation-skip');
    expect(find.text('整轮核对'), findsOneWidget);
    expect(find.text('未作答'), findsWidgets);
    expect(find.text('已核对 2 / 2，写对 0 个，还要练 2 个'), findsOneWidget);
  });

  testWidgets('自动间隔在播报结束后计时，暂停期间不会推进', (tester) async {
    automatic = false;
    await pump(tester);
    await tester.tap(find.text('间隔 10 秒'));
    await tester.pumpAndSettle();
    await start(tester);
    expect(players.length, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('第 1 / 2 题'), findsOneWidget);
    expect(find.byKey(const ValueKey('dictation-countdown')), findsNothing);

    players.single.starts.single();
    players.single.ends.single.complete();
    await tester.pumpAndSettle();
    expect(find.text('10 秒后播报下一题'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('7 秒后播报下一题'), findsOneWidget);
    await tester.tap(find.text('暂停听写'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('第 1 / 2 题'), findsOneWidget);
    expect(find.text('7 秒后播报下一题'), findsOneWidget);
    await tester.tap(find.text('继续听写'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 题'), findsOneWidget);
    expect(players.length, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('重播同一题重置间隔，最后一题留足时间后才进入核对', (tester) async {
    await pump(tester);
    await tester.tap(find.text('间隔 10 秒'));
    await tester.pumpAndSettle();
    await start(tester);
    await tester.pump(const Duration(seconds: 9));
    await tester.tap(find.text('再读一次'));
    await tester.pumpAndSettle();
    expect(find.text('10 秒后播报下一题'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('第 1 / 2 题'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 题'), findsOneWidget);
    expect(find.text('10 秒后结束听写，统一核对'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('整轮核对'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('整轮核对'), findsOneWidget);
  });

  testWidgets('播报失败停在当前题，重试成功才启动自动计时', (tester) async {
    synth.generate = (_) async => throw StateError('synthesis failed');
    await pump(tester);
    await tester.tap(find.text('间隔 10 秒'));
    await tester.pumpAndSettle();
    await start(tester);
    expect(find.text('播报暂时不可用，请点“再读一次”重试。'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('第 1 / 2 题'), findsOneWidget);
    expect(find.byKey(const ValueKey('dictation-countdown')), findsNothing);
    synth.generate = null;
    await tester.tap(find.text('再读一次'));
    await tester.pumpAndSettle();
    expect(find.text('10 秒后播报下一题'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('后台取消正在生成的音频，迟到结果不能播放或自动推进', (tester) async {
    final generated = Completer<Uint8List>();
    synth.generate = (_) => generated.future;
    await pump(tester);
    await tester.tap(find.text('间隔 10 秒'));
    await tester.pumpAndSettle();
    await start(tester);
    expect(find.text('正在准备播报…'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpAndSettle();
    generated.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('第 1 / 2 题'), findsOneWidget);
    expect(players.single.audio, isEmpty);
    expect(players.single.disposed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('听写已暂停'), findsOneWidget);
    await tester.tap(find.text('继续听写'));
    await tester.pumpAndSettle();
    expect(find.text('10 秒后播报下一题'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('档案切换立即停止，不能继续使用上一档案的听写', (tester) async {
    await pump(tester);
    await tester.tap(find.text('间隔 10 秒'));
    await tester.pumpAndSettle();
    await start(tester);
    ProfileScope.switchTo('another-child');
    await tester.pumpAndSettle();
    expect(find.text('档案已切换，请返回后重新开始听写。'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(synth.texts.length, 1);
    expect(find.byKey(const ValueKey('dictation-next')), findsNothing);
  });

  testWidgets('课文更新或移除时停止本轮，避免旧答案与新课文混用', (tester) async {
    await pump(tester);
    await start(tester);
    pack = null;
    container.invalidate(textbookCourseProvider(book.pdfSha256));
    await tester.pumpAndSettle();
    expect(find.text('课文内容已更新或移除，请返回后重新开始听写。'), findsOneWidget);
    expect(find.byKey(const ValueKey('dictation-next')), findsNothing);
  });

  testWidgets('数据恢复令当前听写失效', (tester) async {
    await pump(tester);
    await start(tester);
    await tester.runAsync(() => HiveBoxes.meta.put('practice_draft_epoch', 1));
    await tester.pumpAndSettle();
    expect(find.text('学习数据已恢复，请返回后重新开始听写。'), findsOneWidget);
  });

  testWidgets('深色主题中屏幕手写与核对沿用应用配色', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    await start(tester, handwriting: true);
    expect(
      Theme.of(tester.element(find.byType(WritingCanvas))).brightness,
      Brightness.dark,
    );
    final replay = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '再读一次'),
    );
    final foreground = replay.style!.foregroundColor!
        .resolve(const <WidgetState>{})!.computeLuminance();
    final background = Theme.of(tester.element(find.byType(WritingCanvas)))
        .scaffoldBackgroundColor
        .computeLuminance();
    expect(
      (foreground + 0.05) / (background + 0.05),
      greaterThanOrEqualTo(4.5),
    );
    await tapKey(tester, 'dictation-skip');
    await tapKey(tester, 'dictation-skip');
    expect(find.text('整轮核对'), findsOneWidget);
    expect(find.text('标准字'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旋转改变画布大小后笔迹仍按比例保留，核对时恢复完整笔迹', (tester) async {
    await pump(tester, size: const Size(320, 700));
    await start(tester, handwriting: true);
    final input = find.byKey(const ValueKey('dictation-input-0'));
    await tester.drag(input, const Offset(30, 50));
    await tester.pumpAndSettle();
    final before = tester.widget<WritingCanvas>(input);
    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    final after = tester.widget<WritingCanvas>(input);
    final expected = [
      for (final stroke in before.strokes)
        [for (final point in stroke) point / before.side * after.side],
    ];
    expect(after.strokes, expected);
    await tapKey(tester, 'dictation-next');
    await tapKey(tester, 'dictation-skip');
    final preview = tester.widget<WritingCanvas>(
      find.byKey(const ValueKey('dictation-answer-0')),
    );
    expect(preview.strokes, expected);
  });

  testWidgets('返回时提示本轮不保留，取消退出后仍可继续书写', (tester) async {
    final observer = RouteObserver<ModalRoute<dynamic>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => TextbookDictationPage(
                      bookId: book.pdfSha256,
                      lessonId: 'lesson-001',
                      routeObserver: observer,
                    ),
                  ),
                ),
                child: const Text('进入听写'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('进入听写'));
    await tester.pumpAndSettle();
    await start(tester, handwriting: true);
    final input = find.byKey(const ValueKey('dictation-input-0'));
    await tester.drag(input, const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('结束本次听写？'), findsOneWidget);
    await tester.tap(find.text('留在本轮'));
    await tester.pumpAndSettle();
    expect(find.text('听写已暂停'), findsOneWidget);
    expect(tester.widget<WritingCanvas>(input).strokes.length, 1);
    await tester.tap(find.text('继续听写'));
    await tester.pumpAndSettle();
    expect(tester.widget<WritingCanvas>(input).enabled, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束听写'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookDictationPage), findsNothing);
    expect(find.text('进入听写'), findsOneWidget);
    expect(players.every((player) => player.disposed), isTrue);
  });

  testWidgets('窄屏大字和横屏下两种模式均可完成整轮核对', (tester) async {
    for (final size in [const Size(320, 640), const Size(800, 320)]) {
      for (final handwriting in [false, true]) {
        await pump(tester, size: size, scale: 2);
        await start(tester, handwriting: handwriting);
        await tapKey(tester, handwriting ? 'dictation-skip' : 'dictation-next');
        await tapKey(tester, handwriting ? 'dictation-skip' : 'dictation-next');
        expect(find.text('整轮核对'), findsOneWidget);
        await tapKey(tester, 'dictation-wrong-0');
        await tapKey(tester, 'dictation-correct-1');
        await tapKey(tester, 'dictation-retry-wrong');
        expect(find.text('第 1 / 1 题'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('模式卡片窄屏纵排、宽屏等宽并排，内容使用整屏宽度', (tester) async {
    for (final width in [320.0, 600.0, 800.0, 1200.0]) {
      await pump(tester, size: Size(width, 900));
      final paper = tester.getRect(
        find.byKey(const ValueKey('dictation-mode-paper')),
      );
      final handwriting = tester.getRect(
        find.byKey(const ValueKey('dictation-mode-handwriting')),
      );
      expect(paper.left, SpacingTokens.md);
      expect(handwriting.right, width - SpacingTokens.md);
      if (width >= 600) {
        expect(paper.top, handwriting.top);
        expect(paper.height, handwriting.height);
        expect(paper.width, handwriting.width);
        expect(handwriting.left - paper.right, SpacingTokens.sm);
      } else {
        expect(paper.bottom, lessThan(handwriting.top));
        expect(paper.width, width - SpacingTokens.md * 2);
      }
      final startButton = tester.getRect(
        find.byKey(const ValueKey('dictation-start')),
      );
      expect(startButton.left, SpacingTokens.md);
      expect(startButton.right, width - SpacingTokens.md);
      await tapKey(tester, 'dictation-mode-handwriting');
      expect(find.text('写完后点“写好了”，不会写也可以先跳过。'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('写一写右上入口窄屏仅图标、宽屏显示听写，往返保留课文字卡', (tester) async {
    for (final width in [320.0, 420.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = createAppRouter(
        initialLocation: AppRoutes.textbookContentOf(
          book.pdfSha256,
          'writing',
          [2],
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp.router(
            theme: AppTheme.resolve(
              subject: AppSubject.poem,
              brightness: Brightness.dark,
            ),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('writing-dictation-entry'));
      expect(
        find.descendant(of: find.byType(AppBar), matching: entry),
        findsOneWidget,
      );
      expect(find.text('随机听写'), findsNothing);
      expect(find.textContaining('纸上写或屏幕手写'), findsNothing);
      expect(
        find.descendant(of: entry, matching: find.text('听写')),
        width >= 420 ? findsOneWidget : findsNothing,
      );
      if (width < 420) {
        expect(tester.widget<IconButton>(entry).tooltip, '听写');
      } else {
        final button = tester.widget<TextButton>(entry);
        final foreground = button.style!.foregroundColor!
            .resolve(const <WidgetState>{})!.computeLuminance();
        final background = Theme.of(tester.element(entry))
            .appBarTheme
            .backgroundColor!
            .computeLuminance();
        expect(
          (foreground + 0.05) / (background + 0.05),
          greaterThanOrEqualTo(4.5),
        );
      }
      final appBar = tester.getRect(find.byType(AppBar));
      expect(tester.getCenter(entry).dx, greaterThan(appBar.center.dx));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(TextbookDictationPage), findsOneWidget);
      expect(find.text('听写·星月测试'), findsOneWidget);
      expect(find.text('纸上听写'), findsOneWidget);
      expect(find.text('屏幕手写'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('writing-card-writing-001')),
        findsOneWidget,
      );
      expect(synth.texts, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('同页多课先选择听写课文，进入所选课目', (tester) async {
    final raw = pack!.toJson();
    final second = pack!.lessons.single.toJson()
      ..['id'] = 'lesson-002'
      ..['title'] = '第二课测试';
    for (final category in TextbookCoursePack.categories) {
      second[category] = category == 'writingCharacters'
          ? [
              {
                ...courseFixtureText('writing-003', '日', ['rì']),
                'requirement': 'writing',
              },
            ]
          : <Object>[];
    }
    second['coverage'] = {
      for (final category in TextbookCoursePack.categories)
        category:
            category == 'writingCharacters' ? 'complete' : 'notApplicable',
    };
    (raw['lessons'] as List).add(second);
    final unit = (raw['units'] as List).single as Map<String, dynamic>;
    (unit['lessonIds'] as List).add('lesson-002');
    pack = TextbookCoursePack.fromJson(raw);
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookContentOf(
        book.pdfSha256,
        'writing',
        [2],
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('writing-dictation-entry')));
    await tester.pumpAndSettle();
    expect(find.text('选择听写课文'), findsOneWidget);
    expect(find.byType(TextbookDictationPage), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('选择听写课文'), findsNothing);
    expect(find.byType(TextbookDictationPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('writing-dictation-entry')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('第二课测试'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextbookDictationPage), findsOneWidget);
    expect(find.text('听写·第二课测试'), findsOneWidget);
    expect(find.text('纸上听写'), findsOneWidget);
    expect(find.text('屏幕手写'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('writing-card-writing-001')),
      findsOneWidget,
    );
    expect(synth.texts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本课没有会写字时不显示听写入口', (tester) async {
    final raw = pack!.toJson();
    final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
    lesson['writingCharacters'] = <Object>[];
    (lesson['coverage'] as Map<String, dynamic>)['writingCharacters'] =
        'notApplicable';
    pack = TextbookCoursePack.fromJson(raw);
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookContentOf(
        book.pdfSha256,
        'writing',
        [2],
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('writing-dictation-entry')), findsNothing);
    expect(find.text('原书未要求本课会写字。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
