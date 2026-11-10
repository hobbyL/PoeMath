import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_exercise_repository.dart';
import 'package:poemath/features/textbook/exercise/exercise_providers.dart';
import 'package:poemath/features/textbook/exercise/textbook_exercise_overview.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_course_fixture.dart';

class _DelayedBox extends Fake implements Box<dynamic> {
  final gate = Completer<void>();
  int writes = 0;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      HiveBoxes.settings.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    writes++;
    await gate.future;
    await HiveBoxes.settings.put(key, value);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    ready(),
    isTrue,
    reason:
        '操作应在限定时间内完成：${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).join(" / ")}',
  );
}

void main() {
  late Directory root;
  setUp(() async {
    await setUpHiveForTesting();
    root = await Directory.systemTemp.createTemp('exercise-save-');
  });
  tearDown(() async {
    await tearDownHiveForTesting();
    await root.delete(recursive: true);
  });

  for (final leave in [false, true]) {
    testWidgets('习题保存防连点并保持完整记录，保存途中离页=$leave', (tester) async {
      final book = courseFixtureBook();
      var raw = courseFixtureWithReviewedExercise();
      final exercises =
          ((raw['lessons'] as List).single as Map)['exercises'] as List;
      exercises.add({...exercises.single as Map, 'id': 'exercise-002'});
      raw = reviewTextbookCourse(
        input: raw,
        nodeId: 'exercise-002',
        reviewer: '测试',
        decision: 'approved',
        checks: ['sourcePages', 'content', 'answer'],
        notes: '',
      );
      final pack = TextbookCoursePack.fromJson(raw);
      final courses = TextbookCourseRepository(
        directoryProvider: () async => root,
      );
      final box = _DelayedBox();
      await tester.runAsync(() async {
        await courses.importDraft(book, pack);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              textbookListProvider.overrideWith((_) => [book]),
              textbookCourseRepositoryProvider.overrideWithValue(courses),
              textbookExerciseBoxProvider.overrideWithValue(box),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TextbookExerciseOverview(
                    bookId: book.pdfSha256,
                    lesson: pack.lessons.single,
                    exercises: pack.lessons.single.exercises,
                  ),
                ),
              ),
            ),
          ),
        );
      });
      final buttons = find.widgetWithText(TextButton, '完成');
      await _until(tester, () => buttons.evaluate().length == 2);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TextbookExerciseOverview)),
      );
      final first = tester.widget<TextButton>(buttons.first).onPressed!;
      final second = tester.widget<TextButton>(buttons.last).onPressed!;
      await tester.runAsync(() async {
        first();
        first();
        second();
      });
      await _until(tester, () => box.writes > 0);
      expect(box.writes, 1);
      expect(tester.widget<TextButton>(buttons.last).onPressed, isNull);
      if (leave) await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        box.gate.complete();
      });
      await _until(
        tester,
        () => HiveBoxes.settings.keys.any(
          (k) => k.toString().startsWith('textbook_exercise_v1:'),
        ),
      );
      await drainHiveWritesForTesting(tester);
      if (!leave) {
        await _until(
          tester,
          () =>
              buttons.evaluate().length == 2 &&
              tester.widget<TextButton>(buttons.last).onPressed != null,
        );
        await tester.runAsync(() async {
          tester.widget<TextButton>(buttons.last).onPressed!();
        });
        await _until(tester, () => box.writes == 2);
        await drainHiveWritesForTesting(tester);
        await _until(
          tester,
          () =>
              buttons.evaluate().length == 2 &&
              tester.widget<TextButton>(buttons.last).onPressed != null,
        );
        await _until(
          tester,
          () => !container
              .read(textbookExerciseProgressProvider(book.pdfSha256))
              .isLoading,
        );
        expect(find.textContaining('保存习题记录失败'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      final repository = TextbookExerciseRepository(
        book: book,
        editionId: pack.edition.id,
        courses: courses,
      );
      TextbookExerciseProgress? result;
      await tester.runAsync(() async {
        unawaited(repository.load().then((value) => result = value));
      });
      await _until(tester, () => result != null);
      expect(result!.records.length, leave ? 1 : 2);
      expect(result!.records.values.map((r) => r.attempts), everyElement(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }
}
