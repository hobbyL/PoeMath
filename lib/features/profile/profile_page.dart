// lib/features/profile/profile_page.dart
//
// 层级：features/profile
// 职责：个人中心 — 统计面板 + 成就展示 + 设置入口。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(userStatsProvider);
    final streak = ref.watch(streakProvider);
    final unlockedCount = ref.watch(unlockedAchievementsCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: <Widget>[
          IconButton(
            tooltip: '设置',
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings_rounded),
          ),
          const SizedBox(width: SpacingTokens.sm),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: <Widget>[
            // 用户头像 + 等级
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      stats.levelName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.md,
                      vertical: SpacingTokens.xs,
                    ),
                    decoration: BoxDecoration(
                      color: ColorTokens.poemGold.withValues(alpha: 0.12),
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
                          '${stats.totalStars} 颗星星',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: ColorTokens.poemGold,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),

            // 统计面板
            _buildStatsPanel(context, stats, streak),
            const SizedBox(height: SpacingTokens.lg),

            // 成就展示
            _buildAchievementSection(context, unlockedCount),
            const SizedBox(height: SpacingTokens.md),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsPanel(
    BuildContext context,
    UserStats stats,
    int streak,
  ) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '学习统计',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  '${stats.poemsLearned}',
                  '已学诗词',
                  theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  '${stats.poemsMastered}',
                  '已掌握',
                  theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  '$streak',
                  '连续打卡',
                  theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const Divider(height: SpacingTokens.lg),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  '${stats.mathTotalProblems}',
                  '口算总题',
                  theme.colorScheme.secondary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  stats.mathTotalProblems > 0
                      ? '${(stats.mathAccuracy * 100).toStringAsFixed(0)}%'
                      : '-',
                  '正确率',
                  ColorTokens.success,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  '${stats.longestStreak}',
                  '最长连续',
                  ColorTokens.poemGold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String value,
    String label,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementSection(BuildContext context, int unlockedCount) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: ColorTokens.poemGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        border: Border.all(
          color: ColorTokens.poemGold.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            size: 32,
            color: ColorTokens.poemGold,
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '成就勋章',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  unlockedCount > 0
                      ? '已解锁 $unlockedCount 个成就'
                      : '开始学习，解锁你的第一个成就吧！',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: ColorTokens.poemGold,
          ),
        ],
      ),
    );
  }
}
