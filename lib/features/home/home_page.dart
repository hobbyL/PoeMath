// lib/features/home/home_page.dart
//
// 层级：features/home
// 职责：首页 — 每日概览、连续打卡、快捷入口、今日推荐。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          // 等级徽章
          Padding(
            padding: const EdgeInsets.only(right: SpacingTokens.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.sm,
                  vertical: SpacingTokens.xs,
                ),
                decoration: BoxDecoration(
                  color: ColorTokens.poemGold.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(SpacingTokens.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.stars_rounded,
                      size: 16,
                      color: ColorTokens.poemGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      stats.levelName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: ColorTokens.poemGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 打卡 + 连续天数
            _buildStreakCard(context, streak, isCheckedIn, ref),
            const SizedBox(height: SpacingTokens.md),

            // 学习概览
            _buildStatsOverview(context, stats, learnedPoems),
            const SizedBox(height: SpacingTokens.lg),

            // 快捷入口
            Text(
              '快捷入口',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            _buildQuickActions(context, mistakeCount),
            const SizedBox(height: SpacingTokens.lg),

            // 今日目标
            _buildDailyGoal(context, ref),
            // 底部留白：为 NotchedBottomBar 预留空间 (barHeight + fabTopReserve)
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakCard(
    BuildContext context,
    int streak,
    bool isCheckedIn,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        boxShadow: SpacingTokens.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCheckedIn ? '今日已打卡 ✓' : '今日待打卡',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$streak',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.xs),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '天连续',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
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
                final checkInRepo = ref.read(checkInRepoProvider);
                await checkInRepo.checkInToday();
                ref.invalidate(isCheckedInProvider);
                ref.invalidate(streakProvider);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
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
            color: ColorTokens.poemGold,
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
    return Container(
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      ),
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
            onTap: () => context.go(AppRoutes.studyHub),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Stack(
            children: [
              _QuickActionButton(
                icon: Icons.error_outline_rounded,
                label: '错题本',
                color: theme.colorScheme.error,
                onTap: () => context.push(AppRoutes.mathMistake),
              ),
              if (mistakeCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: ColorTokens.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$mistakeCount',
                      style: const TextStyle(
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

  Widget _buildDailyGoal(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dueReviews = ref.watch(dueReviewCountProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
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
            '背诵 1 首诗词',
            Icons.menu_book_outlined,
          ),
          _buildGoalItem(
            context,
            '完成 1 组口算 (10 题)',
            Icons.calculate_outlined,
          ),
          if (dueReviews > 0)
            _buildGoalItem(
              context,
              '复习 $dueReviews 首待复习诗词',
              Icons.replay_rounded,
            ),
        ],
      ),
    );
  }

  Widget _buildGoalItem(BuildContext context, String text, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: SpacingTokens.sm),
          Text(text, style: theme.textTheme.bodyMedium),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        ),
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
      ),
    );
  }
}
