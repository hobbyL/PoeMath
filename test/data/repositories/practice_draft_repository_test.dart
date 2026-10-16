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
        old.save('math', {'sessionId': 'stale'}), throwsStateError,);
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
          difficulty: 2,),
    ]);
    Future<void> checkpoint() async {
      await UserStatsRepository().recordMathAttempt(
          isCorrect: true, bestStreak: 1, activityId: 'word_attempt:session:0',);
      await problems.recordAttempt('p',
          correct: true, activityId: 'word_library_attempt:session:0',);
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
