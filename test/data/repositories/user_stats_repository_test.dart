// test/data/repositories/user_stats_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late UserStatsRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = UserStatsRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('UserStatsRepository', () {
    test('get 无数据返回默认值', () {
      final stats = repo.get();
      expect(stats.profileId, 'default');
      expect(stats.totalStars, 0);
      expect(stats.level, 0);
    });

    test('getOrCreate 无数据创建并持久化', () async {
      final stats = await repo.getOrCreate();
      expect(stats.profileId, 'default');

      // 验证已持久化
      final loaded = repo.get();
      expect(loaded.totalStars, 0);
    });

    test('save 保存数据', () async {
      final stats = await repo.getOrCreate();
      stats.totalStars = 100;
      await repo.save(stats);

      expect(repo.get().totalStars, 100);
    });

    test('addStars 增加星星', () async {
      await repo.getOrCreate();
      await repo.addStars(10);
      await repo.addStars(5);

      final stats = repo.get();
      expect(stats.totalStars, 15);
      expect(stats.level, 0);
    });

    test('addStars 跨越阈值时同步更新等级', () async {
      await repo.addStars(49);
      expect(repo.get().level, 0);

      await repo.addStars(1);

      final stats = repo.get();
      expect(stats.totalStars, 50);
      expect(stats.level, 1);
      expect(stats.levelName, '秀才');
    });

    test('addStars 一次跨越多个阈值时写入对应等级', () async {
      await repo.addStars(800);

      final stats = repo.get();
      expect(stats.totalStars, 800);
      expect(stats.level, 5);
      expect(stats.levelName, '榜眼');
    });

    test('updateStreak 更新连续打卡', () async {
      await repo.getOrCreate();
      await repo.updateStreak(5);

      final stats = repo.get();
      expect(stats.currentStreak, 5);
      expect(stats.longestStreak, 5);
    });

    test('updateStreak 保留最长记录', () async {
      await repo.getOrCreate();
      await repo.updateStreak(10);
      await repo.updateStreak(3);

      final stats = repo.get();
      expect(stats.currentStreak, 3);
      expect(stats.longestStreak, 10);
    });

    test('updatePoemStats 更新诗词统计', () async {
      await repo.getOrCreate();
      await repo.updatePoemStats(learned: 50, mastered: 20);

      final stats = repo.get();
      expect(stats.poemsLearned, 50);
      expect(stats.poemsMastered, 20);
    });

    test('updatePoemStats 部分更新', () async {
      await repo.getOrCreate();
      await repo.updatePoemStats(learned: 50);

      final stats = repo.get();
      expect(stats.poemsLearned, 50);
      expect(stats.poemsMastered, 0); // 不传则不变
    });

    test('addMathResults 累加口算统计', () async {
      await repo.getOrCreate();
      await repo.addMathResults(problems: 10, correct: 8);
      await repo.addMathResults(problems: 5, correct: 5);

      final stats = repo.get();
      expect(stats.mathTotalProblems, 15);
      expect(stats.mathTotalCorrect, 13);
    });
  });
}
