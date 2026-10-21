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
    return ref.watch(todayPlanProvider).when(
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: SpacingTokens.md,
                children: [
                  Text(
                    '今日任务 ${plan.completedCount}/${plan.tasks.length}',
                    style: theme.textTheme.titleMedium,
                  ),
                  TextButton.icon(
                    onPressed: _configuring ? null : _configure,
                    icon: const Icon(Icons.tune),
                    label: const Text('调整计划'),
                  ),
                ],
              ),
              Text(
                '${plan.grade}年级${plan.semester}册 · 每天首次生成后固定，完成后不补发',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: SpacingTokens.sm),
              if (plan.tasks.isEmpty)
                ColoredCard(
                  color: theme.colorScheme.primary,
                  child: const Text('今天没有待安排的任务，可按自己的节奏学习。'),
                ),
              for (final task in plan.tasks) ...[
                AppTile(
                  icon: task.completed
                      ? Icons.check_circle_outline
                      : _icon(task.kind),
                  iconColor: task.completed
                      ? theme.semantic.success
                      : theme.colorScheme.primary,
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
          ref.read(mathMistakeRepositoryProvider).getById(task.targetId) !=
              null,
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
          await context
              .push<PoemPracticeResult>(AppRoutes.poemReciteOf(task.targetId));
        case TodayTaskKind.review:
          final reviews = ref.read(reviewRepositoryProvider);
          final progress = ref.read(poemProgressRepositoryProvider);
          final stats = ref.read(userStatsRepositoryProvider);
          ref.read(lastPracticeScoreProvider.notifier).state = null;
          final result = await context
              .push<PoemPracticeResult>(AppRoutes.poemQuizOf(task.targetId));
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
                await progress
                    .save(current.copyWith(status: LearningStatus.mastered));
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
                subtitle:
                    unlocked.map((achievement) => achievement.title).join('、'),
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
      final current = repository.config;
      final counts = {
        for (final kind in TodayTaskKind.values) kind: current.countFor(kind),
      };
      final order = List<TodayTaskKind>.of(current.order);

      /// 组装当前 sheet 内状态为配置对象。
      TodayPlanConfig snapshot() => TodayPlanConfig(
            reviewCount: counts[TodayTaskKind.review]!,
            mistakeCount: counts[TodayTaskKind.mistake]!,
            newPoemCount: counts[TodayTaskKind.newPoem]!,
            order: List.of(order),
          );

      /// 落盘并提示。失败不回滚 UI —— 用户刚做的调整保留在 sheet 里，
      /// 只是明确告知没存上（原实现靠「保存计划」按钮，失败路径同一套）。
      Future<void> persist() async {
        try {
          await repository.saveConfig(snapshot());
        } on Object catch (error, stack) {
          AppLogger.e(
            '计划配置保存失败',
            tag: 'TodayPlan',
            error: error,
            stackTrace: stack,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('计划保存失败，请重试')),
            );
          }
        }
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // 关闭即保存：sheet 是模态的，"每次调整立即落盘"与"关闭时落盘"
        // 对用户无感差异，但后者避免连点加减号触发多次写盘与乱序覆盖。
        // PopScope 覆盖系统手势/返回键关闭路径。
        builder: (context) => PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            await persist();
            if (context.mounted) Navigator.pop(context);
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: ParentAccessBoundary(
              child: StatefulBuilder(
                builder: (context, setSheetState) => SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '调整每日计划',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: SpacingTokens.sm),
                        const Text('每类 0–5 项，最多 15 项；数量及顺序从明天起生效。今天的清单保持固定。'),
                        const SizedBox(height: SpacingTokens.md),
                        for (final (index, kind) in order.indexed) ...[
                          AppTile(
                            icon: _icon(kind),
                            iconColor: Theme.of(context).colorScheme.primary,
                            title: kind.label,
                            subtitle: '每天最多 ${counts[kind]} 项',
                            trailing: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: '减少${kind.label}',
                                  onPressed: counts[kind]! > 0
                                      ? () => setSheetState(
                                            () => counts[kind] =
                                                counts[kind]! - 1,
                                          )
                                      : null,
                                  icon: const Icon(Icons.remove),
                                ),
                                Text('${counts[kind]}'),
                                IconButton(
                                  tooltip: '增加${kind.label}',
                                  onPressed: counts[kind]! < 5
                                      ? () => setSheetState(
                                            () => counts[kind] =
                                                counts[kind]! + 1,
                                          )
                                      : null,
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: index > 0
                                    ? () => setSheetState(() {
                                          order[index] = order[index - 1];
                                          order[index - 1] = kind;
                                        })
                                    : null,
                                child: const Text('上移'),
                              ),
                              TextButton(
                                onPressed: index < order.length - 1
                                    ? () => setSheetState(() {
                                          order[index] = order[index + 1];
                                          order[index + 1] = kind;
                                        })
                                    : null,
                                child: const Text('下移'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // 点「关闭」/ 点空白关闭这两条路径由上面的 PopScope 处理；此处兜底
      // 覆盖 builder 之外的关闭（如父级被移除），重复保存是同值覆盖，无害。
      await persist();
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }
}
