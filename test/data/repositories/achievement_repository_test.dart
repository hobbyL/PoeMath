// test/data/repositories/achievement_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late AchievementRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = AchievementRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  Future<void> addAchievement({
    required String id,
    String title = '测试成就',
    bool isUnlocked = false,
    double progress = 0.0,
  }) async {
    await repo.save(Achievement(
      id: id,
      profileId: ProfileScope.currentId,
      title: title,
      isUnlocked: isUnlocked,
      progress: progress,
    ),);
  }

  group('AchievementRepository', () {
    test('getById 无记录返回 null', () {
      expect(repo.getById('streak_7'), isNull);
    });

    test('save 和 getById 正常工作', () async {
      await addAchievement(id: 'streak_7', title: '连续打卡7天');
      final a = repo.getById('streak_7');
      expect(a, isNotNull);
      expect(a!.title, '连续打卡7天');
    });

    test('getAll 只返回当前 profile 的成就', () async {
      await addAchievement(id: 'a1');

      ProfileScope.switchTo('kid2');
      final kid2Repo = AchievementRepository();
      await kid2Repo.save(Achievement(
        id: 'a2',
        profileId: 'kid2',
        title: '另一个',
      ),);

      ProfileScope.reset();
      expect(repo.getAll().length, 1);
    });

    test('getUnlocked 返回已解锁的成就', () async {
      await addAchievement(id: 'a1', isUnlocked: false);
      await addAchievement(id: 'a2', isUnlocked: true);
      await addAchievement(id: 'a3', isUnlocked: true);

      expect(repo.getUnlocked().length, 2);
    });

    test('unlock 解锁成就', () async {
      await addAchievement(id: 'a1');
      await repo.unlock('a1');

      final a = repo.getById('a1')!;
      expect(a.isUnlocked, isTrue);
      expect(a.unlockedAt, isNotNull);
      expect(a.progress, 1.0);
    });

    test('unlock 已解锁的成就不重复处理', () async {
      // 零断言回归：本用例原先只有 `await repo.unlock('a1'); // 应该不抛异常`，
      // 对 `unlock` 的早退守卫（achievement_repository.dart:38
      // `if (achievement.isUnlocked) return;`）毫无验证 —— 删掉那行，
      // `unlockedAt` 会被 `DateTime.now()` 覆盖、`progress` 被重置为 1.0，
      // 而原用例照样通过。
      //
      // 注意不能用 `addAchievement(isUnlocked: true)` 当 fixture：它不设
      // `unlockedAt`，拿 null 当「首次解锁时刻」没法表达真实不变量。
      final firstUnlock = DateTime(2024, 5, 1, 8, 30);
      await repo.save(Achievement(
        id: 'a1',
        profileId: ProfileScope.currentId,
        title: '测试成就',
        isUnlocked: true,
        unlockedAt: firstUnlock,
        progress: 0.4,
      ),);

      await repo.unlock('a1');

      final after = repo.getById('a1')!;
      expect(
        after.unlockedAt,
        firstUnlock,
        reason: '重复 unlock 不得改写首次解锁时刻',
      );
      expect(after.progress, 0.4, reason: '重复 unlock 不得重置进度');
    });

    test('unlock 对不存在的成就无操作', () async {
      // 零断言回归：原先只调用不断言。删掉「不存在则早退」守卫
      // （achievement_repository.dart:37）后，原用例仍绿。
      await addAchievement(id: 'a1');

      await repo.unlock('nonexistent');

      expect(repo.getAll(), hasLength(1), reason: '不得凭空创建记录');
      expect(repo.getById('nonexistent'), isNull);
      expect(
        repo.getById('a1')!.isUnlocked,
        isFalse,
        reason: '不得误解锁其他成就',
      );
    });

    test('updateProgress 更新进度', () async {
      await addAchievement(id: 'a1');
      await repo.updateProgress('a1', 0.5);

      expect(repo.getById('a1')!.progress, 0.5);
    });

    test('updateProgress 达到 1.0 自动解锁', () async {
      await addAchievement(id: 'a1');
      await repo.updateProgress('a1', 1.0);

      final a = repo.getById('a1')!;
      expect(a.isUnlocked, isTrue);
      expect(a.unlockedAt, isNotNull);
    });

    test('updateProgress 值被 clamp 到 [0, 1]', () async {
      await addAchievement(id: 'a1');
      await repo.updateProgress('a1', 1.5);
      expect(repo.getById('a1')!.progress, 1.0);

      await repo.updateProgress('a1', -0.5);
      expect(repo.getById('a1')!.progress, 0.0);
    });

    test('unlockedCount 返回正确数量', () async {
      await addAchievement(id: 'a1', isUnlocked: false);
      await addAchievement(id: 'a2', isUnlocked: true);

      expect(repo.unlockedCount, 1);
    });
  });
}
