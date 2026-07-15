// lib/domain/achievement_checker.dart
//
// 成就检查器：定义所有成就条件，根据用户统计和扩展数据自动解锁/更新进度。

import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/core/utils/profile_scope.dart';

/// 成就检查上下文 — 聚合所有可用于成就判定的数据。
class AchievementCheckContext {
  final UserStats stats;

  /// 本次刚完成的口算练习（用于判定单次全对 / 困难全对）。
  final MathSession? latestSession;

  /// 已攻克的错题数。
  final int resolvedMistakes;

  /// 已完成的艾宾浩斯复习轮次总数（所有诗词累计）。
  final int completedReviewRounds;

  /// 收藏的公式数。
  final int formulaFavorites;

  /// 困难模式累计做题数。
  final int hardModeTotalProblems;

  const AchievementCheckContext({
    required this.stats,
    this.latestSession,
    this.resolvedMistakes = 0,
    this.completedReviewRounds = 0,
    this.formulaFavorites = 0,
    this.hardModeTotalProblems = 0,
  });
}

/// 成就定义。
class AchievementDef {
  final String id;
  final String title;
  final String description;
  final String iconName;
  final String category;

  /// 从 [AchievementCheckContext] 计算当前进度（0.0 ~ 1.0）。
  final double Function(AchievementCheckContext ctx) progressFn;

  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    this.iconName = 'trophy',
    this.category = '',
    required this.progressFn,
  });
}

/// 全部成就定义列表（44 枚）。
class AchievementDefinitions {
  const AchievementDefinitions._();

  static final List<AchievementDef> all = [
    // ══════════════════════════════════════════════════════════
    // 🔥 打卡坚持（4 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'streak_3',
      title: '初露锋芒',
      description: '连续打卡 3 天',
      iconName: 'fire',
      category: '打卡',
      progressFn: (ctx) => (ctx.stats.currentStreak / 3).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'streak_7',
      title: '锲而不舍',
      description: '连续打卡 7 天',
      iconName: 'fire',
      category: '打卡',
      progressFn: (ctx) => (ctx.stats.currentStreak / 7).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'streak_30',
      title: '铁杵成针',
      description: '连续打卡 30 天',
      iconName: 'fire',
      category: '打卡',
      progressFn: (ctx) => (ctx.stats.currentStreak / 30).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'streak_100',
      title: '百日苦读',
      description: '连续打卡 100 天',
      iconName: 'fire',
      category: '打卡',
      progressFn: (ctx) => (ctx.stats.currentStreak / 100).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 📖 诗词学习（6 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'poems_10',
      title: '诗词入门',
      description: '学习 10 首诗词',
      iconName: 'book',
      category: '诗词',
      progressFn: (ctx) => (ctx.stats.poemsLearned / 10).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_50',
      title: '熟读唐诗',
      description: '学习 50 首诗词',
      iconName: 'book',
      category: '诗词',
      progressFn: (ctx) => (ctx.stats.poemsLearned / 50).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_100',
      title: '腹有诗书',
      description: '学习 100 首诗词',
      iconName: 'book',
      category: '诗词',
      progressFn: (ctx) => (ctx.stats.poemsLearned / 100).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_300',
      title: '书山有路',
      description: '学习 300 首诗词',
      iconName: 'book',
      category: '诗词',
      progressFn: (ctx) => (ctx.stats.poemsLearned / 300).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_500',
      title: '学富五车',
      description: '学习 500 首诗词',
      iconName: 'book',
      category: '诗词',
      progressFn: (ctx) => (ctx.stats.poemsLearned / 500).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_1000',
      title: '千古诗仙',
      description: '学习 1000 首诗词',
      iconName: 'crown',
      category: '诗词',
      progressFn: (ctx) => (ctx.stats.poemsLearned / 1000).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 📖 诗词掌握（6 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'poems_master_10',
      title: '倒背如流',
      description: '掌握 10 首诗词',
      iconName: 'star',
      category: '诗词',
      progressFn: (ctx) =>
          (ctx.stats.poemsMastered / 10).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_master_50',
      title: '出口成章',
      description: '掌握 50 首诗词',
      iconName: 'star',
      category: '诗词',
      progressFn: (ctx) =>
          (ctx.stats.poemsMastered / 50).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_master_100',
      title: '满腹经纶',
      description: '掌握 100 首诗词',
      iconName: 'star',
      category: '诗词',
      progressFn: (ctx) =>
          (ctx.stats.poemsMastered / 100).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_master_300',
      title: '才高八斗',
      description: '掌握 300 首诗词',
      iconName: 'star',
      category: '诗词',
      progressFn: (ctx) =>
          (ctx.stats.poemsMastered / 300).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_master_500',
      title: '经史子集',
      description: '掌握 500 首诗词',
      iconName: 'crown',
      category: '诗词',
      progressFn: (ctx) =>
          (ctx.stats.poemsMastered / 500).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'poems_master_1000',
      title: '诗词全才',
      description: '掌握 1000 首诗词',
      iconName: 'crown',
      category: '诗词',
      progressFn: (ctx) =>
          (ctx.stats.poemsMastered / 1000).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 🔄 复习达人（2 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'review_complete_5',
      title: '温故知新',
      description: '完成 5 轮艾宾浩斯复习',
      iconName: 'refresh',
      category: '复习',
      progressFn: (ctx) =>
          (ctx.completedReviewRounds / 5).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'review_complete_20',
      title: '学而时习',
      description: '完成 20 轮艾宾浩斯复习',
      iconName: 'refresh',
      category: '复习',
      progressFn: (ctx) =>
          (ctx.completedReviewRounds / 20).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 🧮 口算题量（5 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'math_100',
      title: '算数小能手',
      description: '完成 100 道口算题',
      iconName: 'calculator',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathTotalProblems / 100).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_500',
      title: '速算达人',
      description: '完成 500 道口算题',
      iconName: 'calculator',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathTotalProblems / 500).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_1000',
      title: '心算大师',
      description: '完成 1000 道口算题',
      iconName: 'calculator',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathTotalProblems / 1000).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_5000',
      title: '千锤百炼',
      description: '完成 5000 道口算题',
      iconName: 'calculator',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathTotalProblems / 5000).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_10000',
      title: '万题斩',
      description: '完成 10000 道口算题',
      iconName: 'crown',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathTotalProblems / 10000).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 🧮 口算正确率（2 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'math_accuracy_90',
      title: '准确无误',
      description: '口算正确率达到 90%（至少做 50 题）',
      iconName: 'target',
      category: '口算',
      progressFn: (ctx) {
        if (ctx.stats.mathTotalProblems < 50) return 0.0;
        return (ctx.stats.mathAccuracy / 0.9).clamp(0.0, 1.0);
      },
    ),
    AchievementDef(
      id: 'math_accuracy_95',
      title: '炉火纯青',
      description: '口算正确率达到 95%（至少做 200 题）',
      iconName: 'target',
      category: '口算',
      progressFn: (ctx) {
        if (ctx.stats.mathTotalProblems < 200) return 0.0;
        return (ctx.stats.mathAccuracy / 0.95).clamp(0.0, 1.0);
      },
    ),

    // ══════════════════════════════════════════════════════════
    // 🧮 单次全对（5 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'math_perfect_15',
      title: '小试牛刀',
      description: '一次练习 15 题全对',
      iconName: 'check_all',
      category: '口算',
      progressFn: (ctx) => _sessionPerfect(ctx, 15),
    ),
    AchievementDef(
      id: 'math_perfect_20',
      title: '势如破竹',
      description: '一次练习 20 题全对',
      iconName: 'check_all',
      category: '口算',
      progressFn: (ctx) => _sessionPerfect(ctx, 20),
    ),
    AchievementDef(
      id: 'math_perfect_30',
      title: '百发百中',
      description: '一次练习 30 题全对',
      iconName: 'check_all',
      category: '口算',
      progressFn: (ctx) => _sessionPerfect(ctx, 30),
    ),
    AchievementDef(
      id: 'math_perfect_50',
      title: '弹无虚发',
      description: '一次练习 50 题全对',
      iconName: 'check_all',
      category: '口算',
      progressFn: (ctx) => _sessionPerfect(ctx, 50),
    ),
    AchievementDef(
      id: 'math_perfect_100',
      title: '天衣无缝',
      description: '一次练习 100 题全对',
      iconName: 'crown',
      category: '口算',
      progressFn: (ctx) => _sessionPerfect(ctx, 100),
    ),

    // ══════════════════════════════════════════════════════════
    // 🧮 连续答对（3 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'math_combo_30',
      title: '三十连斩',
      description: '连续答对 30 题',
      iconName: 'bolt',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathBestStreak / 30).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_combo_50',
      title: '五十连斩',
      description: '连续答对 50 题',
      iconName: 'bolt',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathBestStreak / 50).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_combo_100',
      title: '百战百胜',
      description: '连续答对 100 题',
      iconName: 'crown',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.stats.mathBestStreak / 100).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 🧮 困难挑战（3 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'math_hard_perfect',
      title: '迎难而上',
      description: '困难模式一次全对',
      iconName: 'flame',
      category: '口算',
      progressFn: (ctx) {
        final s = ctx.latestSession;
        if (s == null) return 0.0;
        if (s.difficulty == 'hard' && s.accuracy >= 1.0) return 1.0;
        return 0.0;
      },
    ),
    AchievementDef(
      id: 'math_hard_100',
      title: '难于登天',
      description: '困难模式累计完成 100 题',
      iconName: 'flame',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.hardModeTotalProblems / 100).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'math_hard_500',
      title: '所向披靡',
      description: '困难模式累计完成 500 题',
      iconName: 'crown',
      category: '口算',
      progressFn: (ctx) =>
          (ctx.hardModeTotalProblems / 500).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 📝 错题攻克（2 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'mistakes_resolve_10',
      title: '知错能改',
      description: '攻克 10 道错题',
      iconName: 'repair',
      category: '错题',
      progressFn: (ctx) =>
          (ctx.resolvedMistakes / 10).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'mistakes_resolve_50',
      title: '百炼成钢',
      description: '攻克 50 道错题',
      iconName: 'repair',
      category: '错题',
      progressFn: (ctx) =>
          (ctx.resolvedMistakes / 50).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // 📐 公式收藏（1 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'formula_fav_10',
      title: '公式宝典',
      description: '收藏 10 条公式',
      iconName: 'function',
      category: '公式',
      progressFn: (ctx) =>
          (ctx.formulaFavorites / 10).clamp(0.0, 1.0),
    ),

    // ══════════════════════════════════════════════════════════
    // ⭐ 星星与等级（5 枚）
    // ══════════════════════════════════════════════════════════
    AchievementDef(
      id: 'stars_50',
      title: '星光初现',
      description: '累积 50 颗星星',
      iconName: 'star',
      category: '星星',
      progressFn: (ctx) =>
          (ctx.stats.totalStars / 50).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'stars_500',
      title: '星光璀璨',
      description: '累积 500 颗星星',
      iconName: 'star',
      category: '星星',
      progressFn: (ctx) =>
          (ctx.stats.totalStars / 500).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'stars_2000',
      title: '满天星辰',
      description: '累积 2000 颗星星',
      iconName: 'star',
      category: '星星',
      progressFn: (ctx) =>
          (ctx.stats.totalStars / 2000).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'level_3',
      title: '进士及第',
      description: '达到进士等级',
      iconName: 'medal',
      category: '星星',
      progressFn: (ctx) =>
          (ctx.stats.level / 3).clamp(0.0, 1.0),
    ),
    AchievementDef(
      id: 'level_6',
      title: '金榜题名',
      description: '达到状元等级',
      iconName: 'crown',
      category: '星星',
      progressFn: (ctx) =>
          (ctx.stats.level / 6).clamp(0.0, 1.0),
    ),
  ];

  /// 单次全对判定辅助：latestSession 题数 ≥ [minProblems] 且正确率 100%。
  static double _sessionPerfect(AchievementCheckContext ctx, int minProblems) {
    final s = ctx.latestSession;
    if (s == null) return 0.0;
    if (s.totalProblems >= minProblems && s.accuracy >= 1.0) return 1.0;
    return 0.0;
  }
}

/// 成就检查器：遍历所有成就定义，更新进度并自动解锁。
class AchievementChecker {
  final AchievementRepository _repo;

  AchievementChecker(this._repo);

  /// 根据 [AchievementCheckContext] 检查所有成就，更新进度和解锁状态。
  ///
  /// 返回本次新解锁的成就列表（可用于弹出提示）。
  Future<List<Achievement>> check(AchievementCheckContext ctx) async {
    final newlyUnlocked = <Achievement>[];

    for (final def in AchievementDefinitions.all) {
      final progress = def.progressFn(ctx);

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
      await _repo.updateProgress(def.id, progress);

      // 检查是否刚解锁
      final updated = _repo.getById(def.id);
      if (updated != null && updated.isUnlocked) {
        newlyUnlocked.add(updated);
      }
    }

    return newlyUnlocked;
  }
}
