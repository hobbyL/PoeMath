// lib/features/poem/poem_review_page.dart
//
// 艾宾浩斯复习列表页：展示今日待复习和所有进行中的复习计划。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class PoemReviewPage extends ConsumerWidget {
  const PoemReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewRepo = ref.watch(reviewRepoProvider);
    final dueToday = reviewRepo.getDueToday();
    final active = reviewRepo.getActive();
    // 非今日到期但仍在进行中的
    final dueIds = dueToday.map((s) => s.poemId).toSet();
    final upcoming = active.where((s) => !dueIds.contains(s.poemId)).toList()
      ..sort((a, b) => a.nextReviewDate.compareTo(b.nextReviewDate));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('复习计划')),
      body: dueToday.isEmpty && upcoming.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_available,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    '暂无复习计划',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    '完成诗词测试后会自动创建复习计划',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 艾宾浩斯说明卡片
                  _buildInfoCard(context)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.1, end: 0, duration: 400.ms),
                  const SizedBox(height: SpacingTokens.lg),

                  // 今日待复习
                  if (dueToday.isNotEmpty) ...[
                    _buildSectionTitle(
                      context,
                      '今日待复习',
                      '${dueToday.length} 首',
                      theme.colorScheme.error,
                    ).animate().fadeIn(duration: 300.ms).slideX(
                          begin: -0.1,
                          end: 0,
                          duration: 300.ms,
                        ),
                    const SizedBox(height: SpacingTokens.sm),
                    ...dueToday.asMap().entries.map(
                          (e) => _buildReviewItem(
                            context,
                            ref,
                            e.value,
                            isDue: true,
                          )
                              .animate()
                              .fadeIn(
                                delay: (80 * e.key).ms,
                                duration: 300.ms,
                              )
                              .slideX(
                                begin: 0.1,
                                end: 0,
                                delay: (80 * e.key).ms,
                                duration: 300.ms,
                              ),
                        ),
                    const SizedBox(height: SpacingTokens.lg),
                  ],

                  // 未来复习
                  if (upcoming.isNotEmpty) ...[
                    _buildSectionTitle(
                      context,
                      '即将复习',
                      '${upcoming.length} 首',
                      theme.colorScheme.secondary,
                    ).animate().fadeIn(duration: 300.ms).slideX(
                          begin: -0.1,
                          end: 0,
                          duration: 300.ms,
                        ),
                    const SizedBox(height: SpacingTokens.sm),
                    ...upcoming.asMap().entries.map(
                          (e) => _buildReviewItem(
                            context,
                            ref,
                            e.value,
                            isDue: false,
                          )
                              .animate()
                              .fadeIn(
                                delay: (80 * e.key).ms,
                                duration: 300.ms,
                              )
                              .slideX(
                                begin: 0.1,
                                end: 0,
                                delay: (80 * e.key).ms,
                                duration: 300.ms,
                              ),
                        ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: theme.colorScheme.tertiary,
      child: Row(
        children: [
          Icon(
            Icons.psychology,
            size: 32,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '艾宾浩斯记忆曲线',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  '按 1、3、7、14、30 天间隔复习，完成 5 轮即为牢固掌握',
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

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String badge,
    Color badgeColor,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
          ),
          child: Text(
            badge,
            style: theme.textTheme.labelSmall?.copyWith(
              color: badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewItem(
    BuildContext context,
    WidgetRef ref,
    ReviewSchedule schedule, {
    required bool isDue,
  }) {
    final poem = ref.watch(poemByIdProvider(schedule.poemId));
    final theme = Theme.of(context);

    if (poem == null) return const SizedBox.shrink();

    // 复习轮次标签
    final roundLabel = '第 ${schedule.currentRound + 1} 轮';
    final intervalLabel = schedule.currentRound < ReviewSchedule.intervals.length
        ? '${ReviewSchedule.intervals[schedule.currentRound]} 天'
        : '已完成';

    // 距离下次复习天数
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reviewDay = DateTime(
      schedule.nextReviewDate.year,
      schedule.nextReviewDate.month,
      schedule.nextReviewDate.day,
    );
    final daysUntil = reviewDay.difference(today).inDays;

    String timeLabel;
    if (isDue) {
      timeLabel = '今日复习';
    } else if (daysUntil == 1) {
      timeLabel = '明天';
    } else {
      timeLabel = '$daysUntil 天后';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: AppTile(
        icon: isDue ? Icons.notifications_active : Icons.schedule,
        iconColor: isDue ? theme.colorScheme.error : theme.colorScheme.secondary,
        title: poem.title,
        subtitle: '$roundLabel · 间隔 $intervalLabel · $timeLabel',
        trailing: isDue
            ? FilledButton.tonal(
                onPressed: () => _startReview(context, ref, schedule),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                  ),
                ),
                child: const Text('复习'),
              )
            : Text(
                timeLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        onTap: isDue
            ? () => _startReview(context, ref, schedule)
            : () => context.push(AppRoutes.poemDetailOf(schedule.poemId)),
      ),
    );
  }

  void _startReview(
    BuildContext context,
    WidgetRef ref,
    ReviewSchedule schedule,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '选择复习方式',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                ListTile(
                  leading: const Icon(Icons.record_voice_over),
                  title: const Text('背诵练习'),
                  subtitle: const Text('渐进式背诵：首字提示 → 全隐 → 默写'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateAndComplete(
                      context,
                      ref,
                      schedule,
                      AppRoutes.poemReciteOf(schedule.poemId),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('填空测试'),
                  subtitle: const Text('补全诗句中缺失的文字'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateAndComplete(
                      context,
                      ref,
                      schedule,
                      '${AppRoutes.poemQuizOf(schedule.poemId)}?type=fill',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('选择题'),
                  subtitle: const Text('根据上句选择正确的下句'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateAndComplete(
                      context,
                      ref,
                      schedule,
                      '${AppRoutes.poemQuizOf(schedule.poemId)}?type=choice',
                    );
                  },
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 导航到复习页面，返回后标记复习完成。
  Future<void> _navigateAndComplete(
    BuildContext context,
    WidgetRef ref,
    ReviewSchedule schedule,
    String route,
  ) async {
    await context.push(route);

    // 返回后推进复习计划
    if (context.mounted) {
      final reviewRepo = ref.read(reviewRepoProvider);
      await reviewRepo.completeReview(schedule.poemId);

      // 如果复习全部完成，将状态更新为「已掌握」
      final nextSchedule = reviewRepo.get(schedule.poemId);
      if (nextSchedule != null && nextSchedule.isCompleted) {
        final progressRepo = ref.read(poemProgressRepoProvider);
        final progress = progressRepo.get(schedule.poemId);
        if (progress != null &&
            progress.status != LearningStatus.mastered) {
          progress.status = LearningStatus.mastered;
          await progressRepo.save(progress);

          // 同步更新 UserStats 的已掌握数
          final statsRepo = ref.read(userStatsRepoProvider);
          final masteredCount = progressRepo.masteredCount;
          await statsRepo.updatePoemStats(mastered: masteredCount);
        }
      }

      // 刷新 providers
      ref.invalidate(reviewRepoProvider);
      ref.invalidate(dueReviewCountProvider);
      ref.invalidate(poemProgressProvider(schedule.poemId));
      ref.invalidate(userStatsProvider);

      if (context.mounted) {
        final message = nextSchedule != null && nextSchedule.isCompleted
            ? '🎉 恭喜！该诗词复习全部完成！'
            : '复习已记录 ✓ 下次复习在 '
                '${nextSchedule != null ? _formatNextDate(nextSchedule) : ''}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatNextDate(ReviewSchedule schedule) {
    final d = schedule.nextReviewDate;
    return '${d.month}月${d.day}日';
  }
}
