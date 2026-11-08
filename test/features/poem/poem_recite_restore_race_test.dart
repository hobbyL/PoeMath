import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/restore_coordinator.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/poem/poem_recite_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/recording_sound_service.dart';

// Delay only completion of the real progress write; every learning-data
// repository and both restore services execute the current production code.
class DelayedProgress extends PoemProgressRepository {
  final entered = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<PoemProgress> recordRecitation(
    String poemId, {
    required int level,
    String? activityId,
    DateTime? completedAt,
  }) async {
    final progress = await super.recordRecitation(
      poemId,
      level: level,
      activityId: activityId,
      completedAt: completedAt,
    );
    entered.complete();
    await gate.future;
    return progress;
  }
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    await HiveBoxes.poems.put(
      'audit-race-poem',
      Poem(
        id: 'audit-race-poem',
        title: '审查用合成诗',
        author: '合成作者',
        dynasty: '唐',
        content: '床',
        pinyin: '',
        layer: 'core',
        grade: 1,
      ),
    );
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForWidgetTesting();
  });

  testWidgets('退出背诵后恢复等待完整结算，旧结果不污染恢复数据', (tester) async {
    final progress = DelayedProgress();
    final container = ProviderContainer(
      overrides: [
        soundServiceProvider.overrideWithValue(RecordingSoundService()),
        poemByIdProvider('audit-race-poem')
            .overrideWith((ref) => HiveBoxes.poems.get('audit-race-poem')),
        poemProgressRepoProvider.overrideWithValue(progress),
        writingStrokeDataProvider.overrideWith(
          (ref) => const WritingStrokeAsset({}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const PoemRecitePage(poemId: 'audit-race-poem'),
                  ),
                ),
                child: const Text('打开背诵'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开背诵'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('默写'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('切换键盘输入'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '床');
    await tester.pump();
    await tester.tap(find.text('提交默写'));

    // Pump real Hive IO and the fake UI zone until the real progress write
    // reaches its delayed completion.
    for (var i = 0; i < 100 && !progress.entered.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(progress.entered.isCompleted, isTrue);
    // Use the production AppBar back button, respecting PopScope.
    final route = ModalRoute.of(tester.element(find.byType(PoemRecitePage)));
    expect(route!.popDisposition, RoutePopDisposition.doNotPop); // 先保存草稿再退出。
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    for (
      var i = 0;
      i < 12 && find.byType(PoemRecitePage).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(route.isCurrent, isFalse);
    expect(find.byType(PoemRecitePage), findsNothing);
    expect(find.text('打开背诵'), findsOneWidget);

    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('poemath-audit-restore-race-'),
    ))!;
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final backup = BackupService();
    final history = BackupHistoryService(
      backup: backup,
      directoryProvider: () async => dir,
      keyProvider: () async => List<int>.filled(32, 11),
    );
    final coordinator = RestoreCoordinator(
      backup: backup,
      history: history,
      assistantBarrier: (action) =>
          action(), // No active assistant in this journey.
      reconcile: () async => true,
      invalidate: () {},
    );
    var restored = false;
    Object? restoreError;
    final restoring = coordinator
        .restore(
          backup.inspectJson(
            jsonEncode({
              'version': 1,
              'poemProgress': <Object>[],
              'userStats': <Object>[],
              'checkIns': <Object>[],
              'learningActivities': <Object>[],
              'activitySettlements': <Object>[],
            }),
          ),
        )
        .then(
          (_) {
            restored = true;
          },
          onError: (Object error) {
            restoreError = error;
          },
        );
    try {
      for (var i = 0; i < 50 && !PracticeDraftRepository.isRestoring; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(PracticeDraftRepository.isRestoring, isTrue);
      expect(restored, isFalse);
      expect(restoreError, isNull);
    } finally {
      progress.gate.complete();
    }
    for (var i = 0; i < 250 && !restored && restoreError == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(restoreError, isNull);
    expect(restored, isTrue);
    await restoring;
    expect(HiveBoxes.poemProgress.values, isEmpty);
    expect(HiveBoxes.learningActivities.values, isEmpty);
    expect(HiveBoxes.checkIns.values, isEmpty);
    expect(UserStatsRepository().get().totalStars, 0);
    String? protectedJson;
    Object? readError;
    var readFinished = false;
    final reading =
        (() async {
          final snapshot = (await history.list()).single;
          return history.read(snapshot.id);
        })().then(
          (value) {
            protectedJson = value;
            readFinished = true;
          },
          onError: (Object error) {
            readError = error;
            readFinished = true;
          },
        );
    for (var i = 0; i < 100 && !readFinished; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(readError, isNull);
    expect(readFinished, isTrue);
    await reading;
    final protected = jsonDecode(protectedJson!) as Map<String, dynamic>;
    expect(protected['learningActivities'] as List, hasLength(1));
    expect(((protected['userStats'] as List).single as Map)['totalStars'], 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
    await tester.pump();
    var closed = false;
    final closing = HiveBoxes.close().then((_) {
      closed = true;
    });
    for (var i = 0; i < 100 && !closed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(closed, isTrue);
    await closing;
  });
}
