// lib/features/home/home_page.dart
//
// 层级：features/home
// 职责：首页 — 每日概览、连续打卡、快捷入口、今日推荐。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/home/practice_resume_section.dart';
import 'package:poemath/features/home/today_plan_section.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(userStatsProvider);
    final streak = ref.watch(streakProvider);
    final isCheckedIn = ref.watch(isCheckedInProvider);
    final learnedPoems = ref.watch(learnedCountProvider);
    final mistakeCount = ref.watch(mistakeCountProvider);
    final dueReviews = ref.watch(dueReviewCountProvider);
    final recommendedPoem = ref.watch(dailyRecommendedPoemProvider);
    final theme = Theme.of(context);

    return Scaffold(
      // 本页不用 AppBar：顶部只放应用名 + 等级徽章，占掉整条高度却只承载
      // 一个「当前等级」的展示。应用名移除（底部导航已标明「首页」，
      // 无需重复）；等级徽章移入打卡卡片首行 —— 连续天数、打卡状态、
      // 等级同属「个人进度」，放一起语义一致，且不新增任何高度。
      //
      // 顶部留白由 `AnimatedPageBody` 的默认 md 提供（四边一致），
      // 不需要额外覆盖 —— 去掉 AppBar 后正文紧贴 `MainShell` 的
      // SafeArea 下沿，md 已经足够且与左右对称。
      body: AnimatedPageBody(
        children: [
          // 打卡 + 连续天数
          _buildStreakCard(context, streak, isCheckedIn, stats, ref),
          const SizedBox(height: SpacingTokens.md),

          // 学习概览
          _buildStatsOverview(context, stats, learnedPoems),
          const SizedBox(height: SpacingTokens.lg),

          // 快捷入口
          const PracticeResumeSection(),
          const TodayPlanSection(),
          Text(
            '快捷入口',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          _buildQuickActions(context, mistakeCount),
          const SizedBox(height: SpacingTokens.lg),

          // 今日推荐
          if (recommendedPoem != null) ...[
            Text(
              '今日推荐',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            _buildDailyRecommendation(context, recommendedPoem),
            const SizedBox(height: SpacingTokens.lg),
          ],

          // 复习提醒（有待复习时显示）
          if (dueReviews > 0) ...[
            _buildReviewReminder(context, dueReviews),
            const SizedBox(height: SpacingTokens.lg),
          ],

          // 今日目标
          _buildDailyGoal(context, dueReviews, ref),
          // 底部留白：为底部导航栏预留空间
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStreakCard(
    BuildContext context,
    int streak,
    bool isCheckedIn,
    UserStats stats,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return ColoredCard(
      gradient: LinearGradient(
        colors: [primary, primary.withValues(alpha: 0.6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: SpacingTokens.softShadow,
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isCheckedIn ? '今日已打卡 ✓' : '今日待打卡',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    // 等级徽章（原 AppBar 右上角）。
                    //
                    // 配色刻意用 onPrimary 半透明底 + 白字，而不是沿用原来
                    // 的 `caution` 黄：本卡背景是 primary 绿色渐变，黄字
                    // 压在绿底上对比度不足（实测在暗色主题下更糟）。
                    // 这里用白色系保证在任何主题下都读得清 —— 等级是展示
                    // 信息，可读性优先于配色一致性。
                    _LevelBadge(levelName: stats.levelName),
                  ],
                ),
                const SizedBox(height: SpacingTokens.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$streak',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.xs),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '天连续',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimary
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isCheckedIn)
            FilledButton.tonal(
              onPressed: () async {
                // 读取今日实际完成量
                final todayPoems = ref.read(todayPoemCountProvider);
                final todayMath = ref.read(todayMathCountProvider);

                // 读取每日目标
                final poemGoal = ref.read(dailyPoemGoalProvider);
                final mathGoal = ref.read(dailyMathGoalProvider);

                // 检查是否所有目标都已完成
                final poemDone = todayPoems >= poemGoal;
                final mathDone = todayMath >= mathGoal;

                if (!poemDone || !mathDone) {
                  if (context.mounted) {
                    final missing = <String>[];
                    if (!poemDone) {
                      missing.add('诗词 $todayPoems/$poemGoal 首');
                    }
                    if (!mathDone) {
                      missing.add('口算 $todayMath/$mathGoal 题');
                    }
                    // 先清除已有提示，避免叠加
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '每日目标未完成：${missing.join("、")}',
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                  return;
                }

                final checkInRepo = ref.read(checkInRepoProvider);
                final statsRepo = ref.read(userStatsRepoProvider);
                final messenger = ScaffoldMessenger.of(context);

                // 打卡落库。磁盘满 / Box 损坏时 `Hive.put` 抛 `HiveError`
                // ——`HiveError extends Error` 而非 `Exception`，故捕 `Object`
                // （项目其余页面同一约定）。不捕获的话异常冒泡成 unhandled
                // error，用户只看到按钮弹回、连续天数没涨，会以为没点上而
                // 反复点，损伤「打卡有记录」这一核心信任。
                int newStreak;
                try {
                  await checkInRepo.checkInToday();
                  // 更新连续打卡天数到 UserStats
                  newStreak = checkInRepo.calculateStreak();
                  await statsRepo.updateStreak(newStreak);
                } on Object catch (error, stackTrace) {
                  AppLogger.e(
                    '打卡落库失败',
                    tag: 'Home',
                    error: error,
                    stackTrace: stackTrace,
                  );
                  if (!context.mounted) return;
                  messenger
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('打卡失败，请检查设备存储空间后重试'),
                      ),
                    );
                  return;
                }

                ref.read(soundServiceProvider).play(SoundEffect.checkIn);
                await ref.read(hapticServiceProvider).medium();
                ref.invalidate(isCheckedInProvider);
                ref.invalidate(streakProvider);
                ref.invalidate(userStatsProvider);

                // 成就自动检查。这里失败不影响打卡本身（打卡已落库），
                // 故只记日志不打断庆祝流程。
                var newlyUnlocked = <Achievement>[];
                try {
                  newlyUnlocked = await checkAchievements(ref);
                } on Object catch (error, stackTrace) {
                  AppLogger.e(
                    '打卡后成就检查失败',
                    tag: 'Home',
                    error: error,
                    stackTrace: stackTrace,
                  );
                }
                ref.invalidate(unlockedAchievementsCountProvider);

                if (context.mounted) {
                  // 打卡庆祝；若同时解锁成就，等它关闭后再弹成就庆祝。
                  // await 而非 `Future.delayed(1800ms)` 猜时长：后者一旦短于
                  // 庆祝弹窗自身时长，两窗就会重叠。
                  final checkInDone = showCelebration(
                    context,
                    type: CelebrationType.checkIn,
                    subtitle: '连续打卡 $newStreak 天！继续保持！',
                  );
                  if (newlyUnlocked.isNotEmpty) {
                    unawaited(
                      checkInDone.then((_) async {
                        if (!context.mounted) return;
                        final names =
                            newlyUnlocked.map((a) => a.title).join('、');
                        await showCelebration(
                          context,
                          type: CelebrationType.achievement,
                          subtitle: names,
                        );
                      }),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                // 主色渐变卡片上的按钮：用 onPrimary 而非白色硬编码，
                // 换主题时自动跟随（与下方 `onPrimary` 图标同源）。
                backgroundColor:
                    theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              child: const Text('打卡'),
            ),
          if (isCheckedIn)
            Icon(
              Icons.check_circle_rounded,
              size: 48,
              color: theme.colorScheme.onPrimary,
            ),
        ],
      ),
    );
  }

  Widget _buildStatsOverview(
    BuildContext context,
    UserStats stats,
    int learnedPoems,
  ) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.menu_book_rounded,
            value: '$learnedPoems',
            label: '已学诗词',
            color: primary,
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.calculate_rounded,
            value: '${stats.mathTotalProblems}',
            label: '口算做题',
            color: secondary,
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.star_rounded,
            value: '${stats.totalStars}',
            label: '总星星',
            color: theme.semantic.caution,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: color,
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, int mistakeCount) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;

    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            icon: Icons.menu_book_rounded,
            label: '背诗词',
            color: primary,
            onTap: () => context.go(AppRoutes.poemTab),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: _QuickActionButton(
            icon: Icons.calculate_rounded,
            label: '做口算',
            color: secondary,
            onTap: () => context.go(AppRoutes.mathTab),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: _QuickActionButton(
            icon: Icons.functions_rounded,
            label: '查公式',
            color: primary.withValues(alpha: 0.7),
            onTap: () => context.push(AppRoutes.studyHub),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: double.infinity,
                child: _QuickActionButton(
                  icon: Icons.error_outline_rounded,
                  label: '错题本',
                  color: theme.colorScheme.error,
                  onTap: () => context.push(AppRoutes.mathMistake),
                ),
              ),
              if (mistakeCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$mistakeCount',
                      style: const TextStyle(
                        // 刻意保留白色，不用 `colorScheme.onError`：
                        // 亮色主题下二者同为白，但**暗色主题下 onError 派生为
                        // 深红**（实测 ~#690005），落在同样是红色的 error 圆形
                        // 背景上几乎不可读。徽章背景恒为 `error`（见上方
                        // decoration），故此处用与之恒有对比的白。
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDailyRecommendation(BuildContext context, Poem poem) {
    final theme = Theme.of(context);
    // 取首句（第一个换行前的文本）
    final firstLine = poem.content.split('\n').first.trim();

    return ColoredCard(
      color: theme.colorScheme.primary,
      onTap: () => context.push(AppRoutes.poemDetailOf(poem.id)),
      child: Row(
        children: [
          // 诗词信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  poem.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  '${poem.dynasty} · ${poem.author}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  firstLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          // 右侧图标
          Icon(
            Icons.auto_stories_outlined,
            size: 36,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewReminder(BuildContext context, int count) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: theme.colorScheme.error,
      onTap: () => context.push(AppRoutes.poemReview),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active,
            color: theme.colorScheme.error,
            size: 28,
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count 首诗词待复习',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '按艾宾浩斯记忆曲线，现在是最佳复习时间',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildDailyGoal(
    BuildContext context,
    int dueReviews,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);
    final poemGoal = ref.watch(dailyPoemGoalProvider);
    final mathGoal = ref.watch(dailyMathGoalProvider);
    final todayPoems = ref.watch(todayPoemCountProvider);
    final todayMath = ref.watch(todayMathCountProvider);

    return ColoredCard(
      color: theme.colorScheme.primary,
      width: double.infinity,
      backgroundOpacity: 0.06,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_rounded,
                size: 20,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                '今日目标',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          _buildGoalItem(
            context,
            '背诵 $poemGoal 首诗词',
            Icons.menu_book_outlined,
            current: todayPoems,
            target: poemGoal,
          ),
          _buildGoalItem(
            context,
            '完成 $mathGoal 题口算',
            Icons.calculate_outlined,
            current: todayMath,
            target: mathGoal,
          ),
          if (dueReviews > 0)
            _buildGoalItem(
              context,
              '复习 $dueReviews 首待复习诗词',
              Icons.replay_rounded,
              onTap: () => context.push(AppRoutes.poemReview),
            ),
        ],
      ),
    );
  }

  Widget _buildGoalItem(
    BuildContext context,
    String text,
    IconData icon, {
    VoidCallback? onTap,
    int? current,
    int? target,
  }) {
    final theme = Theme.of(context);
    final done = current != null && target != null && current >= target;
    final content = Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : icon,
            size: 16,
            color: done
                ? theme.semantic.success
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
          if (current != null && target != null)
            Text(
              '$current/$target',
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    done ? theme.semantic.success : theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (onTap != null)
            Icon(
              Icons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
        child: content,
      );
    }
    return content;
  }
}

/// 等级徽章：`⭐ 童生`。
///
/// 原先挂在 AppBar 的 actions 里（黄色系，白底）。AppBar 移除后迁入打卡
/// 卡片的绿色渐变背景上，配色随之改为白色系 —— 见调用点注释。
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.levelName});

  final String levelName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: SpacingTokens.xs,
      ),
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stars_rounded, size: 14, color: onPrimary),
          const SizedBox(width: 4),
          Text(
            levelName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: color,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
