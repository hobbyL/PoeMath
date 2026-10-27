import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/domain/writing_geometry.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';
import 'package:poemath/features/textbook/writing/writing_practice_page.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/writing_fixture.dart';

class MemoryBox extends Fake implements Box<dynamic> {
  final data = <String, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
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
  ) =>
      action(current);
}

void main() {
  late MemoryCourses courses;
  late MemoryBox box;
  late TtsService tts;
  late NarrationSettings settings;
  late NarrationSynth synth;
  late MemoryNarrationCache audioCache;
  late WritingStrokeAsset asset;

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
  });

  tearDown(() async {
    tts.dispose();
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  Future<void> pump(WidgetTester tester, {String targetId = 'writing-001'}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
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
            targetId: targetId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('无笔顺数据时降级：直接进入自由书写，显示提示', (tester) async {
    await pump(tester);
    expect(find.text('写一写 · 星'), findsOneWidget);
    expect(find.byKey(const ValueKey('writing-free')), findsOneWidget);
    expect(find.text('这个字暂时没有笔顺数据，可以自由书写。'), findsOneWidget);
    expect(find.text('看笔顺'), findsNothing);
  });

  testWidgets('自由书写后可核对并请家长确认', (tester) async {
    await pump(tester);
    // 画一笔。
    final canvas = find.byKey(const ValueKey('writing-free'));
    await tester.drag(canvas, const Offset(40, 40));
    await tester.pumpAndSettle();

    await tester.tap(find.text('写好了，看一看'));
    await tester.pumpAndSettle();
    expect(find.text('我写的'), findsOneWidget);
    expect(find.text('参考'), findsOneWidget);
    // 无数据时显示家长核对提示。
    expect(
      find.text('这个字暂时没有笔顺数据，请家长看一看写得对不对。'),
      findsOneWidget,
    );
    // 写入成功时不应出现内容失效提示。
    expect(find.textContaining('写字内容已更新'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('writing-parent-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('家长确认'), findsOneWidget);
    await tester.tap(find.text('写得好'));
    await tester.pumpAndSettle();
    expect(find.text('家长已确认 1 次'), findsNothing);
    expect(find.textContaining('家长已确认'), findsOneWidget);
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