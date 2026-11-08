import 'dart:async';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);
  test('诗词作用域隔离、旧页面写入被拒绝、重开和旧数学键兼容', () async {
    addTearDown(ProfileScope.reset);
    final first = PracticeDraftRepository();
    final second = PracticeDraftRepository();
    const all = '["静夜思","all"]';
    const targeted = '["静夜思","1,3"]';
    first.claim('poemDictation', scope: all);
    first.claim('poemDictation', scope: targeted);
    await first.save('poemDictation', {
      'sessionId': 'all',
      'input': ['床'],
    }, scope: all);
    await first.save('poemDictation', {
      'sessionId': 'targeted',
    }, scope: targeted);
    await first.save('math', {'sessionId': 'math'});
    second.claim('poemDictation', scope: all);
    await second.save('poemDictation', {'sessionId': 'new'}, scope: all);
    await expectLater(
      first.save('poemDictation', {'sessionId': 'stale'}, scope: all),
      throwsStateError,
    );
    await first.remove('poemDictation', scope: all, sessionId: 'all');
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(second.get('poemDictation', scope: all)!['sessionId'], 'new');
    expect(
      second.get('poemDictation', scope: targeted)!['sessionId'],
      'targeted',
    );
    expect(second.get('math')!['sessionId'], 'math');
    expect(second.scopes('poemDictation'), containsAll([all, targeted]));
    ProfileScope.switchTo('another');
    expect(second.scopes('poemDictation'), isEmpty);
    ProfileScope.switchTo('default');
    await PracticeDraftRepository.clearAll();
    expect(second.scopes('poemDictation'), isEmpty);
    await expectLater(
      second.save('poemDictation', {'sessionId': 'old-epoch'}, scope: all),
      throwsStateError,
    );
  });
  test('诗词次数和掌握等级在真正重启后重复结算仍只累计一次', () async {
    final repo = PoemProgressRepository();
    final completed = DateTime(2026, 11, 8, 10);
    await Future.wait([
      repo.recordRecitation(
        'poem',
        level: 3,
        activityId: 'same',
        completedAt: completed,
      ),
      repo.recordRecitation(
        'poem',
        level: 3,
        activityId: 'same',
        completedAt: completed,
      ),
    ]);
    await HiveBoxes.close();
    await HiveBoxes.init();
    await repo.recordRecitation(
      'poem',
      level: 3,
      activityId: 'same',
      completedAt: completed,
    );
    expect(repo.get('poem')!.studyCount, 1);
    expect(repo.get('poem')!.masteryLevel, 3);
    expect(repo.get('poem')!.lastStudiedAt, completed);
    expect(repo.get('poem')!.appliedActivityIds, ['same']);
    await repo.recordStudy('poem', activityId: 'next');
    expect(repo.get('poem')!.studyCount, 2);
  });
  test('恢复先排空完整写入链，期间拒绝新结算，恢复后拒绝旧页面', () async {
    final old = PracticeDraftRepository();
    final entered = Completer<void>();
    final proceed = Completer<void>();
    final writing = expectLater(
      old.guard(() async {
        await HiveBoxes.settings.put('pending_completion', 'progress');
        entered.complete();
        await proceed.future;
        await HiveBoxes.settings.put('pending_completion', 'finished');
      }),
      throwsStateError,
    );
    await entered.future;
    var restoreEntered = false;
    final restoring = PracticeDraftRepository.whileRestoring(() async {
      restoreEntered = true;
      expect(HiveBoxes.settings.get('pending_completion'), 'finished');
      await HiveBoxes.meta.put('practice_draft_epoch', 1);
      await HiveBoxes.settings.delete('pending_completion');
    });
    try {
      await Future<void>.delayed(Duration.zero);
      expect(restoreEntered, isFalse);
      await expectLater(
        PracticeDraftRepository().guard(() async => 1),
        throwsStateError,
      );
    } finally {
      proceed.complete();
    }
    await writing;
    await restoring;
    expect(HiveBoxes.settings.get('pending_completion'), isNull);
    await expectLater(old.guard(() async => 1), throwsStateError);
    expect(await PracticeDraftRepository().guard(() async => 1), 1);
  });
  test('排队前固定快照，重开保留输入，旧题组不能删除新草稿', () async {
    final repo = PracticeDraftRepository();
    final snapshot = <String, dynamic>{
      'sessionId': 'old',
      'input': '4',
      'records': <int>[1],
    };
    final saved = repo.save('math', snapshot);
    (snapshot['records'] as List<int>).add(2);
    await saved;
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(repo.get('math')!['records'], [1]);
    expect(repo.get('math')!['input'], '4');
    await repo.save('math', {'sessionId': 'new', 'input': '7'});
    await repo.remove('math', sessionId: 'old');
    expect(repo.get('math')!['sessionId'], 'new');
    await repo.remove('math', sessionId: 'new');
    expect(repo.exists('math'), isFalse);
  });
  test('恢复清除草稿并拒绝旧页面的写入和删除', () async {
    final old = PracticeDraftRepository();
    await old.save('math', {'sessionId': 'before'});
    await old.save('word', {'sessionId': 'word'});
    await PracticeDraftRepository.clearAll();
    final current = PracticeDraftRepository();
    await current.save('math', {'sessionId': 'after'});
    await expectLater(
      old.save('math', {'sessionId': 'stale'}),
      throwsStateError,
    );
    await expectLater(old.remove('math'), throwsStateError);
    await expectLater(old.guard(() async => 1), throwsStateError);
    expect(current.get('math')!['sessionId'], 'after');
    expect(current.get('word'), isNull);
  });
  test('重开后重放已答题：学习总数与题库作答均只计一次', () async {
    final problems = LlmProblemRepository();
    await problems.addAll([
      LlmProblem(
        id: 'p',
        profileId: 'default',
        questionText: '12减4',
        unit: '个',
        operands: [12, 4],
        operators: ['-'],
        answer: 8,
        explanation: '相减',
        batchId: 'batch',
        createdAt: DateTime(2026, 10),
        grade: 2,
        semester: '上',
        topic: 'subtraction',
        difficulty: 2,
      ),
    ]);
    Future<void> checkpoint() async {
      await UserStatsRepository().recordMathAttempt(
        isCorrect: true,
        bestStreak: 1,
        activityId: 'word_attempt:session:0',
      );
      await problems.recordAttempt(
        'p',
        correct: true,
        activityId: 'word_library_attempt:session:0',
      );
    }

    await checkpoint();
    await HiveBoxes.close();
    await HiveBoxes.init();
    await checkpoint();
    expect(UserStatsRepository().get().mathTotalProblems, 1);
    expect(problems.getById('p')!.attempts, 1);
    expect(problems.getById('p')!.correctCount, 1);
  });
}
