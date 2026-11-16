import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/models/textbook_writing_attempt.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/writing_geometry.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';
import 'package:poemath/features/textbook/writing/writing_jigsaw.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';
import 'package:poemath/features/textbook/writing/writing_practice_page.dart';
import 'package:poemath/features/textbook/writing/textbook_writing_records_page.dart';
import 'package:poemath/features/textbook/writing/writing_attempt_preview.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/recording_learning_activity_repository.dart';
import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/writing_fixture.dart';
import '../../helpers/writing_attempt_fixture.dart';
import '../../helpers/writing_records_test_helper.dart';
import '../../helpers/theme_contrast.dart';
import '../../helpers/writing_jigsaw_test_helper.dart';

class MemoryBox extends Fake implements Box<dynamic> {
  final data = <String, dynamic>{};
  final writes = <String>[];
  bool failNext = false;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    writes.add(value as String);
    if (failNext) {
      failNext = false;
      throw HiveError('disk full');
    }
    data[key as String] = value;
  }
}

class MemoryCourses extends TextbookCourseRepository {
  MemoryCourses(this.current);
  TextbookCoursePack current;
  @override
  Future<TextbookCoursePack?> load(Textbook book) async => current;
  @override
  Future<T> withCurrentPack<T>(
    Textbook book,
    Future<T> Function(TextbookCoursePack?) action,
  ) => action(current);
}

void main() {
  late MemoryCourses courses;
  late MemoryBox box;
  late TtsService tts;
  late NarrationSettings settings;
  late NarrationSynth synth;
  late MemoryNarrationCache audioCache;
  late WritingStrokeAsset asset;
  late WritingStrokeAsset fullAsset;
  late RecordingLearningActivityRepository activityRepository;

  setUpAll(() async => fullAsset = await loadJigsawTestAsset());

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    courses = MemoryCourses(writingFixture());
    box = MemoryBox();
    settings = NarrationSettings();
    synth = NarrationSynth();
    audioCache = MemoryNarrationCache();
    tts = TtsService(
      settings,
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: RecordingNarrationPlayer.new,
    );
    // 只让「星」有笔顺数据，以同时覆盖降级路径。
    asset = const WritingStrokeAsset({});
    activityRepository = RecordingLearningActivityRepository();
  });

  tearDown(() async {
    tts.dispose();
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  WritingProgress savedProgress() => WritingProgress.fromJson(
    jsonDecode(box.data.values.single as String) as Map<String, dynamic>,
  );

  Future<void> pump(
    WidgetTester tester, {
    String targetId = 'writing-001',
    ThemeData? theme,
    Size size = const Size(400, 800),
    double scale = 1,
    bool withRouter = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final route = AppRoutes.textbookWritingOf(
      courseFixtureBook().pdfSha256,
      courses.current.lessons.single.id,
      targetId,
    );
    final router = withRouter
        ? createAppRouter(initialLocation: AppRoutes.mathSessionDetail)
        : null;
    if (router != null) addTearDown(router.dispose);
    Widget builder(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          learningActivityRepositoryProvider.overrideWithValue(
            activityRepository,
          ),
          textbookListProvider.overrideWithValue([courseFixtureBook()]),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
          textbookWritingBoxProvider.overrideWithValue(box),
          writingStrokeDataProvider.overrideWith((ref) => asset),
          textbookFileServiceProvider.overrideWithValue(
            TextbookFileService(narrationAudioCache: audioCache),
          ),
        ],
        child: router != null
            ? MaterialApp.router(
                theme: theme,
                builder: builder,
                routerConfig: router,
              )
            : MaterialApp(
                theme: theme,
                builder: builder,
                home: WritingPracticePage(
                  bookId: courseFixtureBook().pdfSha256,
                  lessonId: courses.current.lessons.single.id,
                  targetId: targetId,
                ),
              ),
      ),
    );
    await tester.pumpAndSettle();
    if (router != null) {
      unawaited(router.push<void>(route));
      await tester.pumpAndSettle();
      expect(
        find.byType(WritingPracticePage),
        findsOneWidget,
        reason: '真实路由进入单字页：${router.routeInformationProvider.value.uri}',
      );
    }
  }

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$subject/$brightness 写字阶段导航的未选中文字也应清晰', (tester) async {
        await pump(
          tester,
          theme: AppTheme.resolve(subject: subject, brightness: brightness),
        );
        expectReadableText(tester, find.text('自己写'));
        expectReadableText(tester, find.text('看一看'));
      });
    }
  }

  testWidgets('无笔顺数据时降级：直接进入自由书写，显示提示', (tester) async {
    await pump(tester);
    expect(find.text('写一写 · 星'), findsNothing);
    expect(find.byKey(const ValueKey('writing-free')), findsOneWidget);
    expect(find.text('这个字暂时没有笔顺数据，可以自由书写。'), findsOneWidget);
    expect(find.text('看笔顺'), findsNothing);
  });

  testWidgets('自由书写后可核对并请家长确认', (tester) async {
    await pump(tester, withRouter: true);
    // 画一笔。
    final canvas = find.byKey(const ValueKey('writing-free'));
    await tester.drag(canvas, const Offset(40, 40));
    await tester.pumpAndSettle();
    final written = tester.widget<WritingCanvas>(canvas);
    final originalStrokes = written.strokes;

    await tester.tap(find.text('写好了，看一看'));
    await tester.pumpAndSettle();
    expect(
      activityRepository.records.values.single.activityType,
      'textbookWriting',
    );
    expect(find.text('我写的'), findsOneWidget);
    expect(find.text('参考'), findsOneWidget);
    // 无数据时显示家长核对提示。
    expect(find.text('这个字暂时没有笔顺数据，请家长看一看写得对不对。'), findsOneWidget);
    // 写入成功时不应出现内容失效提示。
    expect(find.textContaining('写字内容已更新'), findsNothing);
    final attempt = savedProgress().records.values.single.attempts.single;
    expect(attempt.kind, WritingAttemptKind.free);
    expect(
      attempt.strokes.single.first.x,
      closeTo(originalStrokes.single.first.dx / written.side, 0.00001),
    );
    expect(
      attempt.strokes.single.last.y,
      closeTo(originalStrokes.single.last.dy / written.side, 0.00001),
    );
    expect(
      activityRepository.records.values.single.completedAt,
      attempt.completedAt,
    );
    expect(
      activityRepository.records.values.single.durationSeconds,
      attempt.durationSeconds,
    );

    await tester.tap(find.byKey(const ValueKey('writing-records-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookWritingRecordsPage), findsOneWidget);
    expect(writingRecordTexts(tester, 'writing-001'), [
      '星',
      '描红 0 次',
      '自写 1 次',
      '拼装 0 次',
    ]);
    await tester.tap(find.byKey(const ValueKey('writing-record-writing-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('writing-attempt-${attempt.id}')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WritingAttemptPreview>(find.byType(WritingAttemptPreview))
          .attempt
          .toJson(),
      attempt.toJson(),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('我写的'), findsOneWidget);
    expect(activityRepository.records, hasLength(1));
    expect(
      tester.widget<WritingCanvas>(find.byType(WritingCanvas)).strokes,
      originalStrokes,
    );

    await tester.tap(find.byKey(const ValueKey('writing-parent-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('家长确认'), findsOneWidget);
    await tester.tap(find.text('写得好'));
    await tester.pumpAndSettle();
    expect(find.text('家长已确认 1 次'), findsNothing);
    expect(find.textContaining('家长已确认'), findsOneWidget);
    expect(
      savedProgress().records.values.single.attempts.single.id,
      attempt.id,
    );
  });

  testWidgets('家长选择"还要练"不计数', (tester) async {
    await pump(tester);
    await tester.drag(
      find.byKey(const ValueKey('writing-free')),
      const Offset(40, 40),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('写好了，看一看'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('writing-parent-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('还要练'));
    await tester.pumpAndSettle();
    expect(find.textContaining('家长已确认'), findsNothing);
  });

  testWidgets('撤销与清空笔迹', (tester) async {
    await pump(tester);
    final canvas = find.byKey(const ValueKey('writing-free'));
    await tester.drag(canvas, const Offset(30, 30));
    await tester.pumpAndSettle();
    await tester.drag(canvas, const Offset(-30, -20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销一笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    // 清空后不崩溃且仍可写。
    expect(find.byKey(const ValueKey('writing-free')), findsOneWidget);
  });

  testWidgets('一次拖动只记一笔，不随移动事件累加', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          learningActivityRepositoryProvider.overrideWithValue(
            activityRepository,
          ),
          textbookListProvider.overrideWithValue([courseFixtureBook()]),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
          textbookWritingBoxProvider.overrideWithValue(box),
          writingStrokeDataProvider.overrideWith((ref) => asset),
          textbookFileServiceProvider.overrideWithValue(
            TextbookFileService(narrationAudioCache: audioCache),
          ),
        ],
        child: MaterialApp(
          home: WritingPracticePage(
            bookId: courseFixtureBook().pdfSha256,
            lessonId: courses.current.lessons.single.id,
            targetId: 'writing-001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('writing-free'));
    // 逐帧移动，模拟真实书写（此前每个移动事件都追加一笔，7 笔变 116 笔）。
    final gesture = await tester.startGesture(tester.getCenter(canvas));
    for (var i = 0; i < 7; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final widget = tester.widget<WritingCanvas>(
      find.byKey(const ValueKey('writing-free')),
    );
    expect(widget.strokes, hasLength(1));
  });

  testWidgets('找不到目标字时显示错误', (tester) async {
    await pump(tester, targetId: 'missing');
    expect(find.text('找不到这个字'), findsOneWidget);
  });

  for (final kind in [WritingAttemptKind.trace, WritingAttemptKind.free]) {
    testWidgets('$kind 保存失败保留原阶段和笔迹，重试冻结同一作品与时间', (tester) async {
      final isTrace = kind == WritingAttemptKind.trace;
      if (isTrace) asset = fullAsset;
      await pump(tester, size: const Size(320, 568), scale: 2);
      if (isTrace) {
        await tester.tap(find.text('描红'));
        await tester.pumpAndSettle();
      }
      final canvas = find.byKey(
        ValueKey(isTrace ? 'writing-trace' : 'writing-free'),
      );
      await tester.scrollUntilVisible(canvas, 160);
      await tester.drag(canvas, const Offset(30, 25));
      await tester.pumpAndSettle();
      final strokes = tester.widget<WritingCanvas>(canvas).strokes;
      final submit = find.text(isTrace ? '描完了，自己写' : '写好了，看一看');
      await tester.scrollUntilVisible(submit, 160);
      box.failNext = true;
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(box.data, isEmpty);
      expect(activityRepository.records, isEmpty);
      expect(tester.widget<WritingCanvas>(canvas).strokes, strokes);
      final retry = find.text('重试');
      await tester.scrollUntilVisible(retry, -160);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(box.writes, hasLength(2));
      expect(box.writes.first, box.writes.last);
      final record = savedProgress().records.values.single;
      expect(record.attempts.single.kind, kind);
      expect(record.attempts.single.strokes, hasLength(1));
      expect(record.traceCount, isTrace ? 1 : 0);
      expect(record.freeCount, isTrace ? 0 : 1);
      expect(activityRepository.records, hasLength(1));
      if (isTrace) {
        expect(find.byKey(const ValueKey('writing-free')), findsOneWidget);
      } else {
        expect(find.text('我写的'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> openJigsaw(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    double scale = 1,
    ThemeData? theme,
  }) async {
    asset = fullAsset;
    await pump(tester, size: size, scale: scale, theme: theme);
    await tester.tap(find.text('拼一拼'));
    await tester.pumpAndSettle();
  }

  testWidgets('拼装与描红并列，往返后笔迹、已拼碎片和提示选择均保留', (tester) async {
    asset = fullAsset;
    await pump(tester);
    expect(find.byKey(const ValueKey('writing-demo')), findsOneWidget);
    await tester.tap(find.text('描红'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('writing-trace')),
      const Offset(30, 25),
    );
    await tester.pumpAndSettle();
    final traced = tester
        .widget<WritingCanvas>(find.byKey(const ValueKey('writing-trace')))
        .strokes;
    expect(traced, hasLength(1));
    final beforeSwitch = DateTime.now();
    await tester.tap(find.text('拼一拼'));
    await tester.pumpAndSettle();
    final layout = jigsawPainter(tester).layout;
    final id = layout.trayOrder.first;
    await dragJigsawPiece(tester, id);
    await tester.tap(find.text('关闭提示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写一写'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WritingCanvas>(find.byKey(const ValueKey('writing-trace')))
          .strokes,
      traced,
    );
    await tester.tap(find.text('拼一拼'));
    await tester.pumpAndSettle();
    expect(jigsawPainter(tester).layout, same(layout));
    expect(jigsawPainter(tester).placed, {id});
    expect(jigsawPainter(tester).showHint, isFalse);
    expect(box.data, isEmpty);
    await tester.tap(find.text('写一写'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('描完了，自己写'));
    await tester.pumpAndSettle();
    final attempt = savedProgress().records.values.single.attempts.single;
    expect(attempt.kind, WritingAttemptKind.trace);
    expect(attempt.startedAt.isBefore(beforeSwitch), isTrue);
    expect(attempt.strokes, hasLength(1));
  });

  testWidgets('完成拼装记录独立事实和活动，新一轮完成可再次计数', (tester) async {
    await openJigsaw(tester);
    for (final id in jigsawPainter(tester).layout.trayOrder) {
      await dragJigsawPiece(tester, id);
    }
    var record = savedProgress().records.values.single;
    expect(record.puzzleCount, 1);
    expect(record.traceCount, 0);
    expect(record.freeCount, 0);
    expect(record.geometryPasses, 0);
    expect(record.parentConfirms, 0);
    expect(record.nextDay, isNull);
    expect(record.badge, WritingBadge.assembled);
    expect(activityRepository.records, hasLength(1));
    expect(
      activityRepository.records.values.single.activityType,
      'textbookWriting',
    );
    expect(find.text('拼好了！'), findsOneWidget);
    expect(find.textContaining('写字内容已更新'), findsNothing);
    await tester.tap(find.text('再拼一次'));
    await tester.pumpAndSettle();
    for (final id in jigsawPainter(tester).layout.trayOrder) {
      await dragJigsawPiece(tester, id);
    }
    record = savedProgress().records.values.single;
    expect(record.puzzleCount, 2);
    expect(record.parentConfirms, 0);
    expect(activityRepository.records, hasLength(2));
    await tester.tap(find.text('去写一写'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('writing-trace')), findsOneWidget);
  });

  testWidgets('拼装保存失败留在完成页，重试只记一次且成功前不记录活动', (tester) async {
    await openJigsaw(
      tester,
      size: const Size(320, 568),
      scale: 2,
      theme: AppTheme.resolve(
        subject: AppSubject.poem,
        brightness: Brightness.dark,
      ),
    );
    box.failNext = true;
    for (final id in jigsawPainter(tester).layout.trayOrder) {
      await dragJigsawPiece(tester, id);
    }
    expect(box.data, isEmpty);
    expect(activityRepository.records, isEmpty);
    expect(find.text('拼装记录还没保存，请重试。'), findsOneWidget);
    final retry = find.byKey(const ValueKey('jigsaw-save-retry'));
    final board = tester.getRect(find.byKey(const ValueKey('jigsaw-board')));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('jigsaw-board'))), board);
    expect(
      tester
          .hitTestOnBinding(tester.getCenter(retry))
          .path
          .any((entry) => identical(entry.target, tester.renderObject(retry))),
      isTrue,
      reason: '重试保存按钮应可滚动到可点击位置',
    );
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(savedProgress().records.values.single.puzzleCount, 1);
    expect(activityRepository.records, hasLength(1));
    expect(find.text('完整的字拼出来啦。'), findsNothing);
    expect(find.text('去写一写'), findsOneWidget);
    expect(find.text('拼装记录还没保存，请重试。'), findsNothing);
  });

  testWidgets('拼装完成事件的本轮开始时间用于活动时长，不累计上一轮', (tester) async {
    await openJigsaw(tester);
    final firstStart = DateTime.now().subtract(const Duration(seconds: 8));
    final firstEvent = tester.widget<WritingJigsaw>(find.byType(WritingJigsaw));
    expect(
      await firstEvent.onCompleted(
        writingAttemptFixture(
          id: 'stage-puzzle-duration-round-1',
          kind: WritingAttemptKind.puzzle,
          startedAt: firstStart,
          completedAt: DateTime.now(),
        ),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    final first = activityRepository.records.values.single;
    expect(
      first.durationSeconds,
      first.completedAt.difference(firstStart).inSeconds,
    );
    expect(first.durationSeconds, greaterThanOrEqualTo(8));
    final secondStart = DateTime.now().subtract(const Duration(seconds: 2));
    final secondEvent = tester.widget<WritingJigsaw>(
      find.byType(WritingJigsaw),
    );
    expect(
      await secondEvent.onCompleted(
        writingAttemptFixture(
          id: 'stage-puzzle-duration-round-2',
          kind: WritingAttemptKind.puzzle,
          startedAt: secondStart,
          completedAt: DateTime.now(),
        ),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    final second = activityRepository.records.values.last;
    expect(
      second.durationSeconds,
      second.completedAt.difference(secondStart).inSeconds,
    );
    expect(second.durationSeconds, greaterThanOrEqualTo(2));
    expect(second.durationSeconds, lessThan(first.durationSeconds));
  });

  for (final restore in [false, true]) {
    testWidgets('${restore ? '恢复数据' : '档案切换'}后禁用旧拼装页面并保留画面', (tester) async {
      await openJigsaw(
        tester,
        size: const Size(320, 568),
        scale: 2,
        theme: AppTheme.resolve(
          subject: AppSubject.poem,
          brightness: Brightness.dark,
        ),
      );
      final id = jigsawPainter(tester).layout.trayOrder.first;
      await dragJigsawPiece(tester, id);
      if (restore) {
        await tester.runAsync(
          () => PracticeDraftRepository.whileRestoring(
            PracticeDraftRepository.clearAll,
          ),
        );
      } else {
        ProfileScope.switchTo('other');
      }
      await tester.pumpAndSettle();
      expect(
        find.text(restore ? '学习数据已恢复，请重新进入写一写' : '档案已切换，请重新进入写一写'),
        findsOneWidget,
      );
      expect(jigsawPainter(tester).placed, {id});
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('jigsaw-hint-toggle')),
            )
            .onPressed,
        isNull,
      );
      expect(box.data, isEmpty);
    });
  }

  for (final size in [const Size(320, 568), const Size(760, 360)]) {
    testWidgets('整页上下布局大字号仍可拖取全部拼块并完成：$size', (tester) async {
      asset = fullAsset;
      await pump(tester, size: size, scale: 2, withRouter: true);
      final navigation = tester.getRect(find.byType(AppBar));
      final modes = tester.getRect(find.byKey(const ValueKey('writing-mode')));
      expect(navigation.contains(modes.topLeft), isTrue);
      expect(navigation.contains(modes.bottomRight), isTrue);
      final recordsEntry = find.byKey(const ValueKey('writing-records-entry'));
      expect(
        find.descendant(of: find.byType(AppBar), matching: recordsEntry),
        findsOneWidget,
      );
      expect(
        tester.getCenter(recordsEntry).dx,
        greaterThan(tester.getCenter(find.byTooltip('朗读')).dx),
      );
      expectReadableText(tester, find.text('写一写'));
      expectReadableText(tester, find.text('拼一拼'));
      await tester.tap(find.text('拼一拼'));
      await tester.pumpAndSettle();
      final board = tester.getRect(find.byKey(const ValueKey('jigsaw-board')));
      final tray = tester.getRect(find.byKey(const ValueKey('jigsaw-tray')));
      expect(tray.top, greaterThanOrEqualTo(board.bottom));
      expect(tray.center.dx, closeTo(board.center.dx, 0.01));
      if (size.width > size.height) {
        expectLandscapeJigsawControls(tester);
        await tester.tap(find.byKey(const ValueKey('jigsaw-hint-toggle')));
        await tester.pumpAndSettle();
        expect(jigsawPainter(tester).showHint, isFalse);
      }
      expect(find.text('拖动碎片，拼回整字。'), findsNothing);
      final layout = jigsawPainter(tester).layout;
      for (final id in layout.trayOrder) {
        await dragJigsawPiece(tester, id);
      }
      expect(savedProgress().records.values.single.puzzleCount, 1);
      final attempt = savedProgress().records.values.single.attempts.single;
      expect(attempt.puzzle!.pieces, [
        for (final piece in layout.pieces) piece.outline,
      ]);
      expect(attempt.puzzle!.placementOrder, layout.trayOrder);
      expect(attempt.puzzle!.hintEnabled, size.width < size.height);
      expect(find.text('完整的字拼出来啦。'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('writing-records-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(TextbookWritingRecordsPage), findsOneWidget);
      expect(writingRecordTexts(tester, 'writing-001'), [
        '星',
        '描红 0 次',
        '自写 0 次',
        '拼装 1 次',
      ]);
      await tester.tap(
        find.byKey(const ValueKey('writing-record-writing-001')),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('writing-attempt-${attempt.id}'));
      await tester.scrollUntilVisible(row, 160);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final art = find.byType(WritingAttemptPreview);
      await tester.scrollUntilVisible(art, 160);
      await tester.pumpAndSettle();
      expect(
        tester.widget<WritingAttemptPreview>(art).attempt.toJson(),
        attempt.toJson(),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(jigsawPainter(tester).placed, hasLength(6));
      expect(savedProgress().records.values.single.puzzleCount, 1);
      expect(activityRepository.records, hasLength(1));
      if (size.width > size.height) {
        expectLandscapeJigsawControls(tester);
        await tester.tap(find.byKey(const ValueKey('jigsaw-restart')));
        await tester.pumpAndSettle();
        expect(jigsawPainter(tester).placed, isEmpty);
        expect(jigsawPainter(tester).showHint, isFalse);
        expect(savedProgress().records.values.single.puzzleCount, 1);
        expectLandscapeJigsawControls(tester);
      }
      expect(tester.takeException(), isNull);
    });
  }

  group('几何比对（降级前）', () {
    test('笔数不符给出笔画数提示', () {
      final result = checkWriting(
        userStrokes: [
          [const math.Point<double>(0, 0), const math.Point<double>(1, 1)],
        ],
        referenceMedians: [
          [const math.Point<double>(0, 0), const math.Point<double>(1, 0)],
          [const math.Point<double>(0, 0), const math.Point<double>(0, 1)],
        ],
      );
      expect(result.allPassed, isFalse);
      expect(result.fault, StrokeFault.strokesCount);
      expect(result.firstBadStroke, isNull);
      expect(result.expectedStrokes, 2);
      expect(result.actualStrokes, 1);
    });
  });
}
