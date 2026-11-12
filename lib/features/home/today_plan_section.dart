import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/domain/today_plan.dart';
import 'package:poemath/features/home/providers/home_providers.dart' as home;
import 'package:poemath/features/home/providers/today_plan_providers.dart';
import 'package:poemath/features/home/today_plan_editor.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/poem_practice_score.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart' as poem;

class TodayPlanSection extends ConsumerStatefulWidget {
  const TodayPlanSection({super.key});
  @override
  ConsumerState<TodayPlanSection> createState() => _TodayPlanSectionState();
}

class _TodayPlanSectionState extends ConsumerState<TodayPlanSection> {
  bool _opening = false;
  bool _configuring = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adjustPlan = TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(
          kMinInteractiveDimension,
          kMinInteractiveDimension,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.bodySmall?.copyWith(height: 1.2),
      ),
      onPressed: _configuring ? null : _configure,
      child: const Text('调整计划'),
    );
    return ref
        .watch(todayPlanProvider)
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(SpacingTokens.md),
            child: Text('正在准备今日任务…'),
          ),
          error: (error, stack) => AppTile(
            icon: Icons.refresh,
            iconColor: theme.colorScheme.error,
            title: '今日任务暂未读取成功',
            subtitle: '点此重试，已生成的任务不会替换',
            onTap: () => ref.invalidate(todayPlanProvider),
          ),
          data: (plan) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '今日练习清单 ${plan.completedCount}/${plan.tasks.length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  adjustPlan,
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              if (plan.tasks.isEmpty)
                const AppEmptyState(
                  icon: Icons.event_note_outlined,
                  title: '今天没有待安排的任务',
                  description: '可按自己的节奏学习。',
                ),
              if (plan.tasks.isNotEmpty) ...[
                ResponsiveCardGrid(
                  children: [
                    for (final task in plan.tasks)
                      AppTile(
                        icon: task.completed
                            ? Icons.check_circle_outline
                            : _icon(task.kind),
                        iconColor: task.completed
                            ? theme.semantic.success
                            : theme.colorScheme.primary,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        title: '${task.kind.label} · ${task.title}',
                        subtitle: task.completed
                            ? '今日已完成'
                            : _available(task)
                            ? '开始这一项'
                            : '内容已移除，今天不补发',
                        onTap: task.completed || _opening || !_available(task)
                            ? null
                            : () => _open(task),
                        trailing: task.completed || !_available(task)
                            ? const SizedBox.shrink()
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.sm),
              ],
              const SizedBox(height: SpacingTokens.md),
            ],
          ),
        );
  }

  IconData _icon(TodayTaskKind kind) => switch (kind) {
    TodayTaskKind.review => Icons.history_edu,
    TodayTaskKind.mistake => Icons.calculate_outlined,
    TodayTaskKind.newPoem => Icons.menu_book_outlined,
  };

  bool _available(TodayPlanTask task) => switch (task.kind) {
    TodayTaskKind.mistake =>
      ref.read(mathMistakeRepositoryProvider).getById(task.targetId) != null,
    TodayTaskKind.newPoem =>
      ref.read(poemRepositoryProvider).getById(task.targetId) != null,
    TodayTaskKind.review =>
      ref.read(poemRepositoryProvider).getById(task.targetId) != null &&
          ref.read(reviewRepositoryProvider).get(task.targetId) != null,
  };

  Future<void> _open(TodayPlanTask task) async {
    if (_opening) return;
    setState(() => _opening = true);
    final messenger = ScaffoldMessenger.of(context);
    final plan = ref.read(todayPlanProvider).asData?.value;
    try {
      switch (task.kind) {
        case TodayTaskKind.newPoem:
          await context.push<PoemPracticeResult>(
            AppRoutes.poemReciteOf(task.targetId),
          );
        case TodayTaskKind.review:
          final reviews = ref.read(reviewRepositoryProvider);
          final progress = ref.read(poemProgressRepositoryProvider);
          final stats = ref.read(userStatsRepositoryProvider);
          ref.read(lastPracticeScoreProvider.notifier).state = null;
          final result = await context.push<PoemPracticeResult>(
            AppRoutes.poemQuizOf(task.targetId),
          );
          if (!mounted) return;
          final score = ref.read(lastPracticeScoreProvider);
          ref.read(lastPracticeScoreProvider.notifier).state = null;
          if ((result == PoemPracticeResult.quizPassed ||
                  result == PoemPracticeResult.quizFailed) &&
              score != null) {
            await reviews.completeReview(
              task.targetId,
              score: score,
              activityId:
                  'today_plan:${plan?.dateKey}:${task.id}:${task.baseline}',
            );
            if (reviews.get(task.targetId)?.isCompleted == true) {
              final current = progress.get(task.targetId);
              if (current != null &&
                  current.status != LearningStatus.mastered) {
                await progress.save(
                  current.copyWith(status: LearningStatus.mastered),
                );
              }
              await stats.updatePoemStats(mastered: progress.masteredCount);
            }
            if (!mounted) return;
            ref.invalidate(poem.dueReviewCountProvider);
            ref.invalidate(poem.poemProgressProvider(task.targetId));
            ref.invalidate(home.userStatsProvider);
            final unlocked = await checkAchievements(ref);
            if (!mounted) return;
            ref.invalidate(home.unlockedAchievementsCountProvider);
            if (unlocked.isNotEmpty) {
              showCelebration(
                context,
                type: CelebrationType.achievement,
                subtitle: unlocked
                    .map((achievement) => achievement.title)
                    .join('、'),
              );
            }
            if (score < 0.8) {
              messenger.showSnackBar(
                const SnackBar(content: Text('本次测试未达 80%，复习尚未完成，明天再测')),
              );
            }
          }
        case TodayTaskKind.mistake:
          final mistakes = ref.read(mathMistakeRepositoryProvider);
          final mistake = mistakes.getById(task.targetId);
          if (mistake == null) return;
          final result = await showMistakeRepractice(context, mistake);
          if (result != null) {
            await mistakes.recordRepracticeResult(
              task.targetId,
              isCorrect: result,
            );
          }
      }
    } on Object catch (error, stack) {
      AppLogger.e(
        '今日任务打开或保存失败',
        tag: 'TodayPlan',
        error: error,
        stackTrace: stack,
      );
      messenger.showSnackBar(const SnackBar(content: Text('任务未能更新，请重试')));
    } finally {
      if (mounted) {
        ref.invalidate(todayPlanProvider);
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _configure() async {
    if (_configuring) return;
    setState(() => _configuring = true);
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      final repository = ref.read(todayPlanRepositoryProvider);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // 关闭必须经过保存结果，禁止拖动/遮罩直接 pop 绕过失败处理。
        isDismissible: false,
        enableDrag: false,
        builder: (context) => ParentAccessBoundary(
          child: TodayPlanEditor(
            initial: repository.config,
            onSave: repository.saveConfig,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }
}
