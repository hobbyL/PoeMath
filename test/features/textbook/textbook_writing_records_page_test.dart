import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_writing_attempt.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_writing_repository.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/domain/textbook_writing_review.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/textbook_writing_records_page.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';
import 'package:poemath/features/textbook/writing/writing_attempt_preview.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/theme_contrast.dart';
import '../../helpers/writing_fixture.dart';
import '../../helpers/writing_attempt_fixture.dart';
import '../../helpers/writing_records_test_helper.dart';

class _MemoryCourses extends TextbookCourseRepository {
  _MemoryCourses(this.current);
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
  final book = courseFixtureBook();
  late _MemoryCourses courses;
  late TextbookWritingRepository repository;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    courses = _MemoryCourses(writingFixture());
    repository = TextbookWritingRepository(
      book: book,
      editionId: courses.current.edition.id,
      courses: courses,
      hasStrokeData: (_) => false,
    );
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  List<WritingTarget> targets() => writingTargets(
    courses.current,
    courses.current.lessons.single,
    hasStrokeData: (_) => false,
  );

  WritingRecord record({
    String targetId = 'writing-001',
    int traceCount = 0,
    int freeCount = 0,
    int puzzleCount = 0,
    String? fingerprint,
    List<WritingAttempt> attempts = const [],
  }) => WritingRecord(
    fingerprint:
        fingerprint ??
        targets().firstWhere((t) => t.id == targetId).fingerprint,
    traceCount: traceCount,
    freeCount: freeCount,
    puzzleCount: puzzleCount,
    attempts: attempts,
  );

  Future<void> store(
    WidgetTester tester,
    Map<String, WritingRecord> records, {
    String? legacyTarget,
  }) async {
    final progress = WritingProgress(
      profileId: ProfileScope.currentId,
      bookId: book.pdfSha256,
      editionId: courses.current.edition.id,
      records: records,
    );
    final raw = progress.toJson();
    if (legacyTarget != null) {
      final key = WritingProgress.targetKey(
        courses.current.lessons.single.id,
        legacyTarget,
      );
      ((raw['records'] as Map)[key] as Map).remove('puzzleCount');
      ((raw['records'] as Map)[key] as Map).remove('attempts');
    }
    await tester.runAsync(
      () => HiveBoxes.settings.put(repository.key, jsonEncode(raw)),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    String? lessonId,
    String? targetId,
    String? attemptId,
    Future<WritingProgress?> Function()? loadProgress,
    bool settle = true,
    GoRouter? router,
    Size size = const Size(420, 900),
    double scale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget builder(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookListProvider.overrideWithValue([book]),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
          writingStrokeDataProvider.overrideWith(
            (_) async => const WritingStrokeAsset({}),
          ),
          if (loadProgress != null)
            textbookWritingProgressProvider(book.pdfSha256)
                .overrideWith((_) => loadProgress()),
        ],
        child: router == null
            ? MaterialApp(
                theme: theme,
                builder: builder,
                home: TextbookWritingRecordsPage(
                  bookId: book.pdfSha256,
                  lessonId: lessonId ?? courses.current.lessons.single.id,
                  targetId: targetId,
                  attemptId: attemptId,
                ),
              )
            : MaterialApp.router(
                theme: theme,
                builder: builder,
                routerConfig: router,
              ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  String countsText(WidgetTester tester, String targetId) =>
      writingRecordTexts(tester, targetId)
          .where(
            (text) =>
                text.startsWith('描红 ') ||
                text.startsWith('自写 ') ||
                text.startsWith('拼装 '),
          )
          .join('\n');

  const untouched = '描红 0 次\n自写 0 次\n拼装 0 次';

  testWidgets('旧描红自写记录和新拼装记录分别显示，查看不改写存储', (tester) async {
    final lessonId = courses.current.lessons.single.id;
    await store(tester, {
      WritingProgress.targetKey(lessonId, 'writing-001'): record(
        traceCount: 2,
        freeCount: 4,
      ),
      WritingProgress.targetKey(lessonId, 'writing-002'): record(
        targetId: 'writing-002',
        puzzleCount: 5,
      ),
      WritingProgress.targetKey('other-lesson', 'writing-001'): record(
        puzzleCount: 99,
      ),
    }, legacyTarget: 'writing-001');
    final saved = HiveBoxes.settings.get(repository.key);
    await pump(tester);

    expect(writingRecordTexts(tester, 'writing-001'), [
      '星',
      '描红 2 次',
      '自写 4 次',
      '拼装 0 次',
    ]);
    expect(writingRecordTexts(tester, 'writing-002'), [
      '月',
      '描红 0 次',
      '自写 0 次',
      '拼装 5 次',
    ]);
    expect(find.text(courses.current.lessons.single.title), findsNothing);
    expect(find.text('xīng'), findsNothing);
    expect(find.text('yuè'), findsNothing);
    expect(find.byType(ColoredCard), findsNWidgets(2));
    final first = tester.getRect(
      find.byKey(const ValueKey('writing-record-writing-001')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('writing-record-writing-002')),
    );
    expect(first.top, closeTo(second.top, 0.01));
    expect(first.right, lessThan(second.left));
    expect(
      first.top,
      closeTo(
        tester.getRect(find.byType(AppBar)).bottom + SpacingTokens.md,
        0.01,
      ),
    );
    expect(HiveBoxes.settings.get(repository.key), saved);
  });

  testWidgets('忽略已过期的字级记录及其他课目的同目标记录，不清空原存储', (tester) async {
    await store(tester, {
      WritingProgress.targetKey(
        courses.current.lessons.single.id,
        'writing-001',
      ): record(
        traceCount: 8,
        freeCount: 9,
        puzzleCount: 10,
        fingerprint: 'old-content',
      ),
      WritingProgress.targetKey('other-lesson', 'writing-002'): record(
        targetId: 'writing-002',
        puzzleCount: 11,
      ),
    });
    final saved = HiveBoxes.settings.get(repository.key);
    await pump(tester);
    expect(countsText(tester, 'writing-001'), untouched);
    expect(countsText(tester, 'writing-002'), untouched);
    expect(HiveBoxes.settings.get(repository.key), saved);
  });

  testWidgets('新的完成记录通过现有 Hive provider 自动刷新，重新查看不再计数', (tester) async {
    await pump(tester);
    expect(countsText(tester, 'writing-001'), untouched);
    await tester.runAsync(
      () => repository.recordStage(
        lessonId: courses.current.lessons.single.id,
        fingerprint: writingLessonFingerprint(targets()),
        targetId: 'writing-001',
        stage: WritingStageDone.puzzle,
        operationId: 'completed-puzzle',
        expectedRevision: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(countsText(tester, 'writing-001'), '描红 0 次\n自写 0 次\n拼装 1 次');
    final saved = HiveBoxes.settings.get(repository.key);
    await pump(tester);
    expect(countsText(tester, 'writing-001'), '描红 0 次\n自写 0 次\n拼装 1 次');
    expect(HiveBoxes.settings.get(repository.key), saved);
  });

  testWidgets('切换档案自动显示新档案记录，切回来保留原次数', (tester) async {
    await store(tester, {
      WritingProgress.targetKey(
        courses.current.lessons.single.id,
        'writing-001',
      ): record(
        puzzleCount: 3,
      ),
    });
    await pump(tester);
    expect(countsText(tester, 'writing-001'), contains('拼装 3 次'));
    ProfileScope.switchTo('another-child');
    await tester.pumpAndSettle();
    expect(countsText(tester, 'writing-001'), untouched);
    ProfileScope.reset();
    await tester.pumpAndSettle();
    expect(countsText(tester, 'writing-001'), contains('拼装 3 次'));
  });

  testWidgets('读取失败不显示零次，重试后显示原有计数', (tester) async {
    await store(tester, {
      WritingProgress.targetKey(
        courses.current.lessons.single.id,
        'writing-001',
      ): record(
        traceCount: 2,
      ),
    });
    var attempts = 0;
    await pump(
      tester,
      loadProgress: () async {
        if (attempts++ == 0) throw StateError('read failed');
        return repository.load();
      },
    );
    expect(find.text('暂时无法读取练习记录'), findsOneWidget);
    expect(find.byType(ColoredCard), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(countsText(tester, 'writing-001'), contains('描红 2 次'));
    expect(find.text('暂时无法读取练习记录'), findsNothing);
  });

  testWidgets('等待进度期间显示加载状态，成功后显示各字次数', (tester) async {
    final pending = Completer<WritingProgress?>();
    await pump(tester, loadProgress: () => pending.future, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ColoredCard), findsNothing);
    pending.complete(
      WritingProgress(
        profileId: ProfileScope.currentId,
        bookId: book.pdfSha256,
        editionId: courses.current.edition.id,
      ),
    );
    await tester.pumpAndSettle();
    expect(countsText(tester, 'writing-001'), untouched);
  });

  testWidgets('课目已移除时给出返回教材提示', (tester) async {
    await pump(tester, lessonId: 'removed-lesson');
    expect(find.text('本课暂不可用'), findsOneWidget);
    expect(find.byType(ColoredCard), findsNothing);
  });

  testWidgets('本课无会写字时使用统一空状态', (tester) async {
    final raw = courses.current.toJson();
    final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
    lesson['writingCharacters'] = <Object?>[];
    lesson['coverage'] = {
      ...lesson['coverage'] as Map<String, dynamic>,
      'writingCharacters': 'notApplicable',
    };
    courses.current = TextbookCoursePack.fromJson(raw);
    await pump(tester);
    expect(find.text('本课暂无会写字。'), findsOneWidget);
    expect(find.byType(ColoredCard), findsNothing);
  });

  testWidgets('真实应用路由可直达本课已有记录', (tester) async {
    final lessonId = courses.current.lessons.single.id;
    await store(tester, {
      WritingProgress.targetKey(lessonId, 'writing-001'): record(
        puzzleCount: 3,
      ),
    });
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookWritingRecordsOf(
        book.pdfSha256,
        lessonId,
      ),
    );
    addTearDown(router.dispose);
    await pump(tester, router: router);
    final page = tester.widget<TextbookWritingRecordsPage>(
      find.byType(TextbookWritingRecordsPage),
    );
    expect(page.bookId, book.pdfSha256);
    expect(page.lessonId, lessonId);
    expect(countsText(tester, 'writing-001'), contains('拼装 3 次'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击字后按时间回看真实笔迹与当轮拼装，特殊 ID 与返回不改存储', (tester) async {
    final lessonId = courses.current.lessons.single.id;
    final trace = writingAttemptFixture(
      id: 'trace /中文&?#',
      kind: WritingAttemptKind.trace,
      completedAt: DateTime.utc(2026, 11, 14, 9),
    );
    final puzzle = writingAttemptFixture(
      id: 'puzzle-1',
      kind: WritingAttemptKind.puzzle,
    );
    await store(tester, {
      WritingProgress.targetKey(lessonId, 'writing-001'): record(
        traceCount: 1,
        freeCount: 4,
        puzzleCount: 1,
        attempts: [trace, puzzle],
      ),
      WritingProgress.targetKey(lessonId, 'writing-002'): record(
        targetId: 'writing-002',
        freeCount: 1,
        attempts: [writingAttemptFixture(id: 'other-character')],
      ),
    });
    final raw = HiveBoxes.settings.get(repository.key);
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookWritingRecordsOf(
        book.pdfSha256,
        lessonId,
      ),
    );
    addTearDown(router.dispose);
    await pump(tester, router: router);
    await tester.tap(find.byKey(const ValueKey('writing-record-writing-001')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '星·练习记录'), findsOneWidget);
    expect(find.text('星'), findsNothing);
    expect(find.text('xīng'), findsNothing);
    expect(find.text('每次练习'), findsNothing);
    expect(find.byType(ColoredCard), findsNothing);
    expect(find.text('另有 4 次早期练习未保存详情。'), findsOneWidget);
    final traceRow = find.byKey(ValueKey('writing-attempt-${trace.id}'));
    final puzzleRow = find.byKey(ValueKey('writing-attempt-${puzzle.id}'));
    expect(
      tester.getRect(puzzleRow).top,
      closeTo(
        tester.getRect(find.byType(AppBar)).bottom + SpacingTokens.md,
        0.01,
      ),
    );
    expect(
      tester.getTopLeft(puzzleRow).dy,
      lessThan(tester.getTopLeft(traceRow).dy),
    );
    expect(
      find.byKey(const ValueKey('writing-attempt-other-character')),
      findsNothing,
    );
    await tester.scrollUntilVisible(traceRow, 160);
    await tester.tap(traceRow);
    await tester.pumpAndSettle();
    final page = tester.widget<TextbookWritingRecordsPage>(
      find.byType(TextbookWritingRecordsPage),
    );
    expect(page.targetId, 'writing-001');
    expect(page.attemptId, trace.id);
    expect(find.text('星 · 描红'), findsOneWidget);
    expect(find.textContaining('用时 1 分 5 秒'), findsOneWidget);
    final art = find.byKey(const ValueKey('writing-attempt-artwork'));
    await tester.scrollUntilVisible(art, 160);
    await tester.pumpAndSettle();
    final painter =
        tester.widget<CustomPaint>(art).painter! as TianziGridPainter;
    final side = tester.getSize(art).width;
    expect(painter.userStrokes, hasLength(2));
    expect(painter.userStrokes.first.first.dx, closeTo(side * 0.1, 0.01));
    expect(painter.userStrokes.first.first.dy, closeTo(side * 0.2, 0.01));
    expect(painter.strokeWidth, closeTo(side * 0.0125, 0.001));
    expect(painter.referenceStrokes, trace.referenceStrokes);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(puzzleRow, 160);
    await tester.tap(puzzleRow);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('writing-attempt-pieces-toggle'));
    await tester.scrollUntilVisible(toggle, 160);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final puzzlePainter =
        tester.widget<CustomPaint>(art).painter! as WritingPuzzleResultPainter;
    expect(puzzlePainter.showPieceBorders, isTrue);
    expect(puzzlePainter.attempt.puzzle!.pieces, puzzle.puzzle!.pieces);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('练习记录'), findsOneWidget);
    expect(HiveBoxes.settings.get(repository.key), raw);
    expect(HiveBoxes.learningActivities.values, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧练习详情为空时保留累计并说明，新字显示可开始练习的空状态', (tester) async {
    await store(tester, {
      WritingProgress.targetKey(
        courses.current.lessons.single.id,
        'writing-001',
      ): record(
        freeCount: 3,
      ),
    }, legacyTarget: 'writing-001');
    final raw = HiveBoxes.settings.get(repository.key);
    await pump(tester);
    expect(countsText(tester, 'writing-001'), contains('自写 3 次'));
    await pump(tester, targetId: 'writing-001');
    expect(find.text('以前的练习未保存详情'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '星·练习记录'), findsOneWidget);
    expect(find.byType(ColoredCard), findsNothing);
    expect(find.byType(WritingAttemptPreview), findsNothing);
    expect(HiveBoxes.settings.get(repository.key), raw);
    await pump(tester, targetId: 'writing-002');
    expect(find.text('还没有练习作品'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '月·练习记录'), findsOneWidget);
    expect(find.byType(ColoredCard), findsNothing);
  });

  testWidgets('目标或作品不存在时不能展示其他字的详情', (tester) async {
    await store(tester, {
      WritingProgress.targetKey(
        courses.current.lessons.single.id,
        'writing-001',
      ): record(
        freeCount: 1,
        attempts: [writingAttemptFixture()],
      ),
    });
    await pump(tester, targetId: 'missing', attemptId: 'attempt-1');
    expect(find.text('这个字的记录暂不可用'), findsOneWidget);
    await pump(tester, targetId: 'writing-002', attemptId: 'attempt-1');
    expect(find.text('该次练习详情暂不可用'), findsOneWidget);
    expect(find.byType(WritingAttemptPreview), findsNothing);
  });

  testWidgets('档案切换后正在查看的作品立即失效，返回原档案才重新可见', (tester) async {
    await store(tester, {
      WritingProgress.targetKey(
        courses.current.lessons.single.id,
        'writing-001',
      ): record(
        freeCount: 1,
        attempts: [writingAttemptFixture()],
      ),
    });
    await pump(tester, targetId: 'writing-001', attemptId: 'attempt-1');
    expect(find.byType(WritingAttemptPreview), findsOneWidget);
    ProfileScope.switchTo('other');
    await tester.pumpAndSettle();
    expect(find.byType(WritingAttemptPreview), findsNothing);
    expect(find.text('该次练习详情暂不可用'), findsOneWidget);
    ProfileScope.reset();
    await tester.pumpAndSettle();
    expect(find.byType(WritingAttemptPreview), findsOneWidget);
  });

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      for (final size in [const Size(320, 568), const Size(760, 360)]) {
        testWidgets('$subject/$brightness $size 双倍字号可以滚动读取各字完整记录', (
          tester,
        ) async {
          await store(tester, {
            WritingProgress.targetKey(
              courses.current.lessons.single.id,
              'writing-001',
            ): record(
              traceCount: 123456,
              freeCount: 4,
              puzzleCount: 5,
              attempts: [
                writingAttemptFixture(id: 'writing-1'),
                writingAttemptFixture(
                  id: 'puzzle-1',
                  kind: WritingAttemptKind.puzzle,
                ),
              ],
            ),
          });
          final router = createAppRouter(
            initialLocation: AppRoutes.textbookWritingRecordsOf(
              book.pdfSha256,
              courses.current.lessons.single.id,
            ),
          );
          addTearDown(router.dispose);
          await pump(
            tester,
            router: router,
            size: size,
            scale: 2,
            theme: AppTheme.resolve(subject: subject, brightness: brightness),
          );
          expectReadableText(tester, find.textContaining('描红 123456 次'));
          final second = find.byKey(
            const ValueKey('writing-record-writing-002'),
          );
          await tester.ensureVisible(second);
          await tester.pumpAndSettle();
          expect(countsText(tester, 'writing-002'), untouched);
          for (final label in untouched.split('\n')) {
            final text = find.descendant(
              of: second,
              matching: find.text(label),
            );
            final bounds = tester.getRect(text);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
            expect(bounds.bottom, lessThanOrEqualTo(size.height));
            expectReadableText(tester, text);
          }
          final first = find.byKey(
            const ValueKey('writing-record-writing-001'),
          );
          await tester.ensureVisible(first);
          await tester.tap(first);
          await tester.pumpAndSettle();
          for (final id in ['writing-1', 'puzzle-1']) {
            final row = find.byKey(ValueKey('writing-attempt-$id'));
            await tester.scrollUntilVisible(row, 160);
            await tester.tap(row);
            await tester.pumpAndSettle();
            final artwork = find.byKey(
              const ValueKey('writing-attempt-artwork'),
            );
            await tester.scrollUntilVisible(artwork, 160);
            await tester.pumpAndSettle();
            final bounds = tester.getRect(artwork);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
            expect(
              bounds.top,
              greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
            );
            expect(bounds.bottom, lessThanOrEqualTo(size.height));
            if (id == 'puzzle-1') {
              final toggle = find.byKey(
                const ValueKey('writing-attempt-pieces-toggle'),
              );
              await tester.scrollUntilVisible(toggle, 160);
              await tester.tap(toggle);
              await tester.pumpAndSettle();
              expectReadableText(tester, find.text('隐藏碎片'));
              final painter =
                  tester.widget<CustomPaint>(artwork).painter!
                      as WritingPuzzleResultPainter;
              expect(painter.showPieceBorders, isTrue);
            }
            expect(tester.takeException(), isNull);
            await tester.pageBack();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
