import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/textbook_writing_overview.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/writing_fixture.dart';

void main() {
  late TextbookCoursePack pack;
  late WritingStrokeAsset asset;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    pack = writingFixture();
    // 空资产：两个字都无笔顺数据，但仍能正常出卡（AC6 前置条件）。
    asset = const WritingStrokeAsset({});
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  Future<void> pump(
    WidgetTester tester, {
    TextbookCoursePack? courses,
    WritingProgress? progress,
    ValueChanged<String>? onPractice,
    Size size = const Size(420, 900),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final package = courses ?? pack;
    final bookId = courseFixtureBook().pdfSha256;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookListProvider.overrideWithValue([courseFixtureBook()]),
          textbookCourseProvider(bookId).overrideWith((_) async => package),
          writingStrokeDataProvider.overrideWith((_) async => asset),
          textbookWritingProgressProvider(bookId)
              .overrideWith((_) async => progress),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TextbookWritingOverview(
                bookId: bookId,
                lesson: package.lessons.single,
                onPractice: onPractice,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  WritingRecord record({
    int traceCount = 0,
    int freeCount = 0,
    int geometryPasses = 0,
    int parentConfirms = 0,
    String? nextDay,
  }) =>
      WritingRecord(
        fingerprint: 'fp',
        traceCount: traceCount,
        freeCount: freeCount,
        geometryPasses: geometryPasses,
        parentConfirms: parentConfirms,
        nextDay: nextDay,
      );

  WritingProgress progressWith(Map<String, WritingRecord> records) =>
      WritingProgress(
        profileId: ProfileScope.currentId,
        bookId: courseFixtureBook().pdfSha256,
        editionId: pack.edition.id,
        records: records,
      );

  testWidgets('字卡展示田字格大字与「去练字」入口', (tester) async {
    final practiced = <String>[];
    await pump(tester, onPractice: practiced.add);

    for (final id in ['writing-001', 'writing-002']) {
      expect(find.byKey(ValueKey('writing-card-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('writing-practice-$id')), findsOneWidget);
      final card = tester.widget<ColoredCard>(
        find.byKey(ValueKey('writing-card-$id')),
      );
      expect(card.onTap, isNotNull, reason: '整卡可进入练字');
    }
    expect(find.text('星'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    // 字号随田字格边长缩放：字符墨迹约占格子 72%，不再是小字配大格。
    final gridSide = tester
        .getSize(find.byKey(const ValueKey('writing-grid-writing-001')))
        .shortestSide;
    final fontSize = tester.widget<Text>(find.text('星')).style!.fontSize!;
    expect(fontSize / gridSide, closeTo(0.72, 0.01));
    expect(fontSize, greaterThan(80), reason: '160pt 卡片的格子应撑满字身');
    // 拼音只保留在无障碍标签里，卡面不再显示。
    expect(find.text('xīng'), findsNothing);
    expect(find.text('yuè'), findsNothing);
    expect(find.byKey(const ValueKey('writing-masonry')), findsOneWidget);
    expect(find.text('未练'), findsNWidgets(2));
    expect(find.text('今日复习'), findsNothing);

    // 「未练」与「去练字」同一行：底边中心纵坐标一致。
    final badgeY = tester.getCenter(
      find.byKey(const ValueKey('writing-badge-writing-001')),
    );
    final entryY = tester.getCenter(
      find.byKey(const ValueKey('writing-practice-writing-001')),
    );
    expect((badgeY.dy - entryY.dy).abs(), lessThan(SpacingTokens.md));

    await tester
        .tap(find.byKey(const ValueKey('writing-practice-writing-002')));
    await tester.pumpAndSettle();
    expect(practiced, ['writing-002']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('进度小标按记录显示未练 / 已描红 / 已自写', (tester) async {
    final lesson = pack.lessons.single;
    await pump(
      tester,
      progress: progressWith({
        WritingProgress.targetKey(lesson.id, 'writing-001'): record(
          traceCount: 1,
        ),
        WritingProgress.targetKey(lesson.id, 'writing-002'): record(
          geometryPasses: 1,
        ),
      }),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('writing-badge-writing-001')))
          .data,
      '已描红',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('writing-badge-writing-002')))
          .data,
      '已自写',
    );
    expect(find.text('未练'), findsNothing);
    expect(find.text('今日复习'), findsNothing);
  });

  testWidgets('家长确认过且到了复习日显示「今日复习」', (tester) async {
    final lesson = pack.lessons.single;
    await pump(
      tester,
      progress: progressWith({
        WritingProgress.targetKey(lesson.id, 'writing-001'): record(
          parentConfirms: 1,
          nextDay: '2020-01-01',
        ),
      }),
    );

    expect(
      find.byKey(const ValueKey('writing-due-writing-001')),
      findsOneWidget,
    );
    expect(find.text('今日复习'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('writing-badge-writing-001')))
          .data,
      '已自写',
    );
    // 无记录的字不显示复习标记。
    expect(
      find.byKey(const ValueKey('writing-due-writing-002')),
      findsNothing,
    );
  });

  testWidgets('字卡不提供朗读按钮，点击任意位置直接进入练字', (tester) async {
    final practiced = <String>[];
    await pump(tester, onPractice: practiced.add);

    // 写一写是书写活动：卡面不再出现喇叭，也不应创建朗读入口。
    expect(
      find.byKey(const ValueKey('writing-audio-writing-001')),
      findsNothing,
    );
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);

    // 点田字格字身：整卡可点，直接进入练字。
    await tester.tap(
      find.byKey(const ValueKey('writing-grid-writing-001')),
    );
    await tester.pumpAndSettle();
    expect(practiced, ['writing-001']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无会写字时显示空态且不渲染卡片', (tester) async {
    final raw = pack.toJson();
    final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
    lesson['writingCharacters'] = <Object?>[];
    lesson['coverage'] = {
      ...(lesson['coverage'] as Map<String, dynamic>),
      'writingCharacters': 'notApplicable',
    };
    await pump(tester, courses: TextbookCoursePack.fromJson(raw));

    expect(find.byKey(const ValueKey('writing-empty')), findsOneWidget);
    expect(find.text('本课暂无会写字。'), findsOneWidget);
    expect(find.byType(ColoredCard), findsNothing);
    expect(find.text('去练字'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏两倍字号不溢出且整卡可进入', (tester) async {
    final practiced = <String>[];
    await pump(
      tester,
      onPractice: practiced.add,
      size: const Size(320, 640),
      scale: 2,
    );

    final card = find.byKey(const ValueKey('writing-card-writing-001'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('writing-practice-writing-001')),
      findsOneWidget,
      reason: '「去练字」作为视觉指引仍在',
    );
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(practiced, ['writing-001']);
    expect(tester.takeException(), isNull);
  });
}
