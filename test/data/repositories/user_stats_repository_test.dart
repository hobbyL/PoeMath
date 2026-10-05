// test/data/repositories/user_stats_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';

import '../../helpers/hive_test_helper.dart';

/// 模拟旧版本（mathBestStreak 字段加入前）的 UserStats 序列化：
/// 只写 10 个字段，不写字段 10。用于构造真实落盘的旧格式帧。
class _LegacyUserStatsAdapter extends TypeAdapter<UserStats> {
  @override
  final typeId = 13;

  @override
  void write(BinaryWriter writer, UserStats obj) {
    writer
      ..writeByte(10) // 旧版本字段数（索引 0..9）
      ..writeByte(0)
      ..write(obj.profileId)
      ..writeByte(1)
      ..write(obj.totalStars)
      ..writeByte(2)
      ..write(obj.currentStreak)
      ..writeByte(3)
      ..write(obj.longestStreak)
      ..writeByte(4)
      ..write(obj.poemsLearned)
      ..writeByte(5)
      ..write(obj.poemsMastered)
      ..writeByte(6)
      ..write(obj.mathTotalProblems)
      ..writeByte(7)
      ..write(obj.mathTotalCorrect)
      ..writeByte(8)
      ..write(obj.level)
      ..writeByte(9)
      ..write(obj.createdAt);
  }

  @override
  UserStats read(BinaryReader reader) => throw UnimplementedError();
}

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

    test('addStars 同一活动并发重放只奖励一次', () async {
      await Future.wait([
        repo.addStars(3, activityId: 'poem-quiz-1'),
        repo.addStars(3, activityId: 'poem-quiz-1'),
      ]);

      expect(repo.get().totalStars, 3);
    });

    test('addStars 不同活动分别奖励', () async {
      await repo.addStars(2, activityId: 'poem-quiz-1');
      await repo.addStars(3, activityId: 'poem-quiz-2');

      expect(repo.get().totalStars, 5);
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

    test('settleMathChallenge 一次结算挑战统计和奖励', () async {
      final stats = await repo.getOrCreate();
      stats.mathTotalProblems = 10;
      stats.mathTotalCorrect = 8;
      stats.mathBestStreak = 4;
      stats.totalStars = 49;
      await stats.save();

      final settled = await repo.settleMathChallenge(
        problems: 12,
        correct: 11,
        bestStreak: 7,
        stars: 2,
      );

      expect(settled.mathTotalProblems, 22);
      expect(settled.mathTotalCorrect, 19);
      expect(settled.mathBestStreak, 7);
      expect(settled.totalStars, 51);
      expect(settled.level, 1);
    });

    test('settleMathChallenge 不降低历史最佳连击', () async {
      final stats = await repo.getOrCreate();
      stats.mathBestStreak = 20;
      await stats.save();

      await repo.settleMathChallenge(
        problems: 5,
        correct: 4,
        bestStreak: 3,
        stars: 1,
      );

      expect(repo.get().mathBestStreak, 20);
    });

    test('settleMathChallenge 同一活动并发重放只结算一次', () async {
      await Future.wait([
        repo.settleMathChallenge(
          activityId: 'challenge-1',
          problems: 10,
          correct: 9,
          bestStreak: 5,
          stars: 2,
        ),
        repo.settleMathChallenge(
          activityId: 'challenge-1',
          problems: 10,
          correct: 9,
          bestStreak: 5,
          stars: 2,
        ),
      ]);

      final stats = repo.get();
      expect(stats.mathTotalProblems, 10);
      expect(stats.mathTotalCorrect, 9);
      expect(stats.totalStars, 2);
    });

    test('settleMathChallenge 不同活动分别结算', () async {
      for (final id in ['challenge-1', 'challenge-2']) {
        await repo.settleMathChallenge(
          activityId: id,
          problems: 5,
          correct: 4,
          bestStreak: 3,
          stars: 1,
        );
      }

      expect(repo.get().mathTotalProblems, 10);
      expect(repo.get().totalStars, 2);
    });
  });

  group('UserStats 旧记录兼容（R8）', () {
    const compatBoxName = 'user_stats_compat_test';

    /// 用旧版 adapter 真实落盘一条缺 fields[10] 的记录。
    Future<void> writeLegacyRecord(UserStats stats) async {
      Hive.registerAdapter(_LegacyUserStatsAdapter(), override: true);
      final box = await Hive.openBox<UserStats>(compatBoxName);
      await box.put('legacy', stats);
      await box.close();
      // 立即恢复新 adapter，避免影响后续测试
      Hive.registerAdapter(UserStatsAdapter(), override: true);
    }

    test('缺 fields[10] 的旧版记录读取不抛异常且 mathBestStreak 回落为 0',
        () async {
      await writeLegacyRecord(
        UserStats(
          profileId: 'default',
          totalStars: 5,
          currentStreak: 3,
          longestStreak: 9,
          poemsLearned: 10,
          poemsMastered: 4,
          mathTotalProblems: 100,
          mathTotalCorrect: 90,
          level: 2,
          createdAt: DateTime(2024, 1, 1),
        ),
      );

      // 用当前（新）adapter 重开 box 读取旧格式记录
      final box = await Hive.openBox<UserStats>(compatBoxName);
      addTearDown(box.close);
      final stats = box.get('legacy');

      expect(stats, isNotNull);
      expect(stats!.profileId, 'default');
      expect(stats.mathBestStreak, 0, reason: '缺字段必须回落 defaultValue 0');
      expect(stats.mathTotalProblems, 100);
      expect(stats.mathTotalCorrect, 90);
      expect(stats.level, 2);
      expect(stats.totalStars, 5);
      expect(stats.createdAt, DateTime(2024, 1, 1));
    });

    test('新记录含 fields[10] 时正常读取', () async {
      await Hive.deleteBoxFromDisk(compatBoxName);
      final repoBox = await Hive.openBox<UserStats>(compatBoxName);
      await repoBox.put(
        'modern',
        UserStats(profileId: 'default', mathBestStreak: 7),
      );
      await repoBox.close();

      final box = await Hive.openBox<UserStats>(compatBoxName);
      addTearDown(box.close);
      expect(box.get('modern')!.mathBestStreak, 7);
    });
  });
}
