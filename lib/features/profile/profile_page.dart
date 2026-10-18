// lib/features/profile/profile_page.dart
//
// 层级：features/profile
// 职责：个人中心 — 统计面板 + 成就展示 + 设置入口。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/providers/hive_key_recovery_providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(userStatsProvider);
    final streak = ref.watch(streakProvider);
    final unlockedCount = ref.watch(unlockedAchievementsCountProvider);
    final keyRecovered = ref.watch(hiveKeyRecoveredProvider);

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
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: <Widget>[
            // 密钥丢失降级提示（一次性）。放最顶：它是本次启动唯一需要
            // 用户知道的事，不能压在统计卡片下面。
            if (keyRecovered) ...[
              _HiveKeyRecoveredNotice(),
              const SizedBox(height: SpacingTokens.md),
            ],

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
                      color: theme.semantic.caution.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(SpacingTokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.stars_rounded,
                          size: 16,
                          color: theme.semantic.caution,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${stats.totalStars} 颗星星',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.semantic.caution,
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
            const SizedBox(height: SpacingTokens.md),

            // 学习报告 + 学习日历 + 成就勋章（一行三个卡片）
            Row(
              children: [
                Expanded(
                  child: ColoredCard(
                    color: theme.colorScheme.primary,
                    onTap: () => context.push(AppRoutes.learningStats),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bar_chart_rounded,
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: SpacingTokens.sm),
                        Text(
                          '学习报告',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: ColoredCard(
                    color: theme.semantic.caution,
                    onTap: () => context.push(AppRoutes.learningCalendar),
                    child: Column(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 32,
                          color: theme.semantic.caution,
                        ),
                        const SizedBox(height: SpacingTokens.sm),
                        Text(
                          '学习日历',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: _buildAchievementCard(context, theme, unlockedCount),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 本周学习周报
            AppTile(
              icon: Icons.insert_chart_outlined,
              iconColor: theme.colorScheme.tertiary,
              title: '本周学习周报',
              subtitle: '查看本周学习汇总与趋势',
              onTap: () => context.push(AppRoutes.weeklyReport),
            ),
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

    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        children: [
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
                  theme.semantic.success,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  '${stats.mathBestStreak}',
                  '最佳连对',
                  theme.semantic.caution,
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

  Widget _buildAchievementCard(
    BuildContext context,
    ThemeData theme,
    int unlockedCount,
  ) {
    return ColoredCard(
      color: theme.semantic.caution,
      onTap: () => context.push(AppRoutes.achievements),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_rounded,
            size: 32,
            color: theme.semantic.caution,
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            '成就勋章',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「本地数据已重建」一次性提示。
///
/// 为什么是 `StatefulWidget`：提示要「显示过就清除」，而清除必须等**真的
/// 渲染出来之后**。在 `build` 里直接清会在首帧构建失败/被丢弃时把提示
/// 永久吞掉；因此放到 `addPostFrameCallback`（首帧已提交之后）执行。
///
/// 为什么是独立的两个回调：
/// - 如果将来它被移出 `AnimatedPageBody` 的动画子树而单独出现，`initState`
///   里的安排仍会生效；
/// - 如果仍留在动画子树里、首帧并未真正弹出，则交给 `onShown` 在动画真正
///   开始时清除。两条路都只清一次（`_cleared` 兜底）。
class _HiveKeyRecoveredNotice extends StatefulWidget {
  @override
  State<_HiveKeyRecoveredNotice> createState() => _HiveKeyRecoveredNoticeState();
}

class _HiveKeyRecoveredNoticeState extends State<_HiveKeyRecoveredNotice> {
  bool _cleared = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _clear());
  }

  /// 清除标记。幂等：两条清除路径可能都触发。
  ///
  /// 不等待 Future —— 清除是副作用，页面不需要为它阻塞；失败时由
  /// `markHiveKeyRecoveryShown` 自己记日志（最坏结果是下次再提示一遍）。
  void _clear() {
    if (_cleared) return;
    _cleared = true;
    unawaited(markHiveKeyRecoveryShown());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: theme.semantic.caution,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.semantic.caution,
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本地学习记录已重置',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  '设备的加密密钥丢失，之前的学习记录已无法读取，'
                  '已为你重新开始。若曾有备份，可在「设置 - 备份与恢复」中导入。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
