import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_writing_repository.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/domain/textbook_writing_review.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/textbook_writing_records_page.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/theme_contrast.dart';
import '../../helpers/writing_fixture.dart';

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
  }) => WritingRecord(
    fingerprint:
        fingerprint ??
        targets().firstWhere((t) => t.id == targetId).fingerprint,
    traceCount: traceCount,
    freeCount: freeCount,
    puzzleCount: puzzleCount,
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
    }
    await tester.runAsync(
      () => HiveBoxes.settings.put(repository.key, jsonEncode(raw)),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    String? lessonId,
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

  String subtitle(WidgetTester tester, String targetId) => tester
      .widget<AppTile>(find.byKey(ValueKey('writing-record-$targetId')))
      .subtitle;

  const untouched = '描红 0 次 · 未完成\n自写 0 次 · 未完成\n拼装 0 次 · 未完成';

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

    expect(
      subtitle(tester, 'writing-001'),
      '描红 2 次 · 已完成\n自写 4 次 · 已完成\n拼装 0 次 · 未完成',
    );
    expect(
      subtitle(tester, 'writing-002'),
      '描红 0 次 · 未完成\n自写 0 次 · 未完成\n拼装 5 次 · 已完成',
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('writing-record-writing-001')))
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('writing-record-writing-002')),
            )
            .dy,
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
    expect(subtitle(tester, 'writing-001'), untouched);
    expect(subtitle(tester, 'writing-002'), untouched);
    expect(HiveBoxes.settings.get(repository.key), saved);
  });

  testWidgets('新的完成记录通过现有 Hive provider 自动刷新，重新查看不再计数', (tester) async {
    await pump(tester);
    expect(subtitle(tester, 'writing-001'), untouched);
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
    expect(
      subtitle(tester, 'writing-001'),
      '描红 0 次 · 未完成\n自写 0 次 · 未完成\n拼装 1 次 · 已完成',
    );
    final saved = HiveBoxes.settings.get(repository.key);
    await pump(tester);
    expect(
      subtitle(tester, 'writing-001'),
      '描红 0 次 · 未完成\n自写 0 次 · 未完成\n拼装 1 次 · 已完成',
    );
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
    expect(subtitle(tester, 'writing-001'), contains('拼装 3 次 · 已完成'));
    ProfileScope.switchTo('another-child');
    await tester.pumpAndSettle();
    expect(subtitle(tester, 'writing-001'), untouched);
    ProfileScope.reset();
    await tester.pumpAndSettle();
    expect(subtitle(tester, 'writing-001'), contains('拼装 3 次 · 已完成'));
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
    expect(find.byType(AppTile), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(subtitle(tester, 'writing-001'), contains('描红 2 次 · 已完成'));
    expect(find.text('暂时无法读取练习记录'), findsNothing);
  });

  testWidgets('等待进度期间显示加载状态，成功后显示未完成的字', (tester) async {
    final pending = Completer<WritingProgress?>();
    await pump(tester, loadProgress: () => pending.future, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AppTile), findsNothing);
    pending.complete(
      WritingProgress(
        profileId: ProfileScope.currentId,
        bookId: book.pdfSha256,
        editionId: courses.current.edition.id,
      ),
    );
    await tester.pumpAndSettle();
    expect(subtitle(tester, 'writing-001'), untouched);
  });

  testWidgets('课目已移除时给出返回教材提示', (tester) async {
    await pump(tester, lessonId: 'removed-lesson');
    expect(find.text('本课暂不可用'), findsOneWidget);
    expect(find.byType(AppTile), findsNothing);
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
    expect(find.byType(AppTile), findsNothing);
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
    expect(subtitle(tester, 'writing-001'), contains('拼装 3 次 · 已完成'));
    expect(tester.takeException(), isNull);
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
            ),
          });
          await pump(
            tester,
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
          expect(subtitle(tester, 'writing-002'), untouched);
          final text = find.descendant(
            of: second,
            matching: find.text(untouched),
          );
          final bounds = tester.getRect(text);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(size.width));
          expect(bounds.bottom, lessThanOrEqualTo(size.height));
          expectReadableText(tester, text);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
