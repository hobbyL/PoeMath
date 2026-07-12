// lib/domain/achievement_checker.dart
//
// 成就检查器：定义所有成就条件，根据用户统计数据自动解锁/更新进度。

import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/core/utils/profile_scope.dart';

/// 成就定义。
class AchievementDef {
  final String id;
  final String title;
  final String description;
  final String iconName;

  /// 从 UserStats 计算当前进度（0.0 ~ 1.0）。
  final double Function(UserStats stats) progressFn;

  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    this.iconName = 'trophy',
    required this.progressFn,
  });
}

/// 全部成就定义列表。
class AchievementDefinitions {
  const AchievementDefinitions._();

  static final List<AchievementDef> all = [
    // ======== 打卡 ========
    AchievementDef(
      id: 'streak_3',
      title: '初露锋芒',
      description: '连续打卡 3 天',
      iconName: 'fire',
      progressFn: (s) => (s.currentStreak / 3).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'streak_7',
      title: '锲而不舍',
      description: '连续打卡 7 天',
      iconName: 'fire',
      progressFn: (s) => (s.currentStreak / 7).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'streak_30',
      title: '铁杵成针',
      description: '连续打卡 30 天',
      iconName: 'fire',
      progressFn: (s) => (s.currentStreak / 30).clamp(0.0, 1.0),
    ),

    // ======== 诗词 ========
    AchievementDef(
      id: 'poems_10',
      title: '诗词入门',
      description: '学习 10 首诗词',
      iconName: 'book',
      progressFn: (s) => (s.poemsLearned / 10).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_50',
      title: '熟读唐诗',
      description: '学习 50 首诗词',
      iconName: 'book',
      progressFn: (s) => (s.poemsLearned / 50).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_100',
      title: '腹有诗书',
      description: '学习 100 首诗词',
      iconName: 'book',
      progressFn: (s) => (s.poemsLearned / 100).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_master_10',
      title: '倒背如流',
      description: '掌握 10 首诗词',
      iconName: 'star',
      progressFn: (s) => (s.poemsMastered / 10).clamp(0.0, 1.0),
    ),

    // ======== 口算 ========
    AchievementDef(
      id: 'math_100',
      title: '算数小能手',
      description: '完成 100 道口算题',
      iconName: 'calculator',
      progressFn: (s) => (s.mathTotalProblems / 100).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_500',
      title: '速算达人',
      description: '完成 500 道口算题',
      iconName: 'calculator',
      progressFn: (s) => (s.mathTotalProblems / 500).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_1000',
      title: '心算大师',
      description: '完成 1000 道口算题',
      iconName: 'calculator',
      progressFn: (s) => (s.mathTotalProblems / 1000).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_accuracy_90',
      title: '准确无误',
      description: '口算正确率达到 90%（至少做 50 题）',
      iconName: 'target',
      progressFn: (s) {
        if (s.mathTotalProblems < 50) return 0.0;
        return (s.mathAccuracy / 0.9).clamp(0.0, 1.0);
      },
    ),

    // ======== 星星 / 等级 ========
    AchievementDef(
      id: 'stars_50',
      title: '星光初现',
      description: '累积 50 颗星星',
      iconName: 'star',
      progressFn: (s) => (s.totalStars / 50).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'stars_500',
      title: '星光璀璨',
      description: '累积 500 颗星星',
      iconName: 'star',
      progressFn: (s) => (s.totalStars / 500).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'level_3',
      title: '进士及第',
      description: '达到进士等级',
      iconName: 'medal',
      progressFn: (s) => (s.level / 3).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'level_6',
      title: '金榜题名',
      description: '达到状元等级',
      iconName: 'crown',
      progressFn: (s) => (s.level / 6).clamp(0.0, 1.0),
    ),
  ];
}

/// 成就检查器：遍历所有成就定义，更新进度并自动解锁。
class AchievementChecker {
  final AchievementRepository _repo;

  AchievementChecker(this._repo);

  /// 根据最新 UserStats 检查所有成就，更新进度和解锁状态。
  ///
  /// 返回本次新解锁的成就列表（可用于弹出提示）。
  Future<List<Achievement>> check(UserStats stats) async {
    final newlyUnlocked = <Achievement>[];

    for (final def in AchievementDefinitions.all) {
      final progress = def.progressFn(stats);

      // 确保成就记录存在
      var achievement = _repo.getById(def.id);
      if (achievement == null) {
        achievement = Achievement(
          id: def.id,
          profileId: ProfileScope.currentId,
          title: def.title,
          description: def.description,
          iconName: def.iconName,
          progress: progress,
        );
        await _repo.save(achievement);
      }

      // 已解锁的不再更新
      if (achievement.isUnlocked) continue;

      // 更新进度
      final wasUnlocked = achievement.isUnlocked;
      await _repo.updateProgress(def.id, progress);

      // 检查是否刚解锁
      final updated = _repo.getById(def.id);
      if (updated != null && updated.isUnlocked && !wasUnlocked) {
        newlyUnlocked.add(updated);
      }
    }

    return newlyUnlocked;
  }
}
