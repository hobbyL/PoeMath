import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/repositories/challenge_record_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late ChallengeRecordRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = ChallengeRecordRepository();
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  test('保存后可按 ID 获取并保留星星', () async {
    await repo.save(_record(id: 'one', stars: 2));

    final record = repo.getById('one');
    expect(record, isNotNull);
    expect(record!.starsEarned, 2);
  });

  test('普通和竖式的最高分分别统计，历史筛选互不混入', () async {
    await repo.save(_record(id: 'normal'));
    final vertical = ChallengeRecord(
      id: 'vertical',
      profileId: 'default',
      mode: 'fixed',
      calculationMode: 'vertical',
      score: 20,
      totalAnswered: 2,
      correctCount: 2,
      bestCombo: 2,
      grade: 2,
      semester: '上',
      difficulty: 'medium',
      durationSeconds: 60,
    );
    await repo.save(vertical);
    expect(repo.bestScore('fixed', calculationMode: 'normal'), 80);
    expect(repo.bestScore('fixed', calculationMode: 'vertical'), 20);
    expect(
      repo.getByMode('fixed', calculationMode: 'vertical').map((r) => r.id),
      ['vertical'],
    );
  });

  test('旧记录兼容默认 0 星', () {
    expect(_record(id: 'legacy').starsEarned, 0);
  });

  test('今日题量只包含当前 profile 的今日挑战', () async {
    // 固定「今日」：给仓储注入固定时钟，记录与该时刻同一天即可。
    // **不要**在测试里硬编码日历日期 —— 真实日期越过那天零点后，记录会
    // 落到「昨天」，断言必然失败（而非偶发）。
    final today = DateTime(2026, 10, 13, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    repo = ChallengeRecordRepository(now: () => today);

    await repo.save(_record(id: 'today', total: 8, createdAt: today));
    await repo.save(
      _record(id: 'yesterday', total: 20, createdAt: yesterday),
    );
    await HiveBoxes.challengeRecords.put(
      'kid2_today',
      _record(
        id: 'today',
        profileId: 'kid2',
        total: 30,
        createdAt: today,
      ),
    );

    expect(repo.todayProblems, 8);
  });

  test('困难模式题量按当前 profile 聚合', () async {
    await repo.save(_record(id: 'hard-1', total: 12, difficulty: 'hard'));
    await repo.save(_record(id: 'hard-2', total: 5, difficulty: 'hard'));
    await repo.save(_record(id: 'medium', total: 30));
    await HiveBoxes.challengeRecords.put(
      'kid2_hard',
      _record(
        id: 'hard',
        profileId: 'kid2',
        total: 40,
        difficulty: 'hard',
      ),
    );

    expect(repo.hardModeTotalProblems, 17);
  });
}

ChallengeRecord _record({
  required String id,
  String profileId = 'default',
  int total = 10,
  int stars = 0,
  String difficulty = 'medium',
  DateTime? createdAt,
}) {
  return ChallengeRecord(
    id: id,
    profileId: profileId,
    mode: 'fixed',
    score: 80,
    totalAnswered: total,
    correctCount: total,
    bestCombo: total,
    grade: 1,
    semester: '上',
    difficulty: difficulty,
    durationSeconds: 60,
    starsEarned: stars,
    createdAt: createdAt,
  );
}
