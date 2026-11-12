// lib/features/home/home_page.dart
//
// 层级：features/home
// 职责：首页 — 每日概览、连续打卡、快捷入口、今日推荐。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/domain/daily_goal_activity.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/home/home_check_in_header.dart';
import 'package:poemath/features/home/practice_resume_section.dart';
import 'package:poemath/features/home/today_plan_section.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(userStatsProvider);
    final streak = ref.watch(streakProvider);
    final isCheckedIn = ref.watch(isCheckedInProvider);
    final learnedPoems = ref.watch(learnedCountProvider);
    final mistakeCount = ref.watch(mistakeCountProvider);
    final dueReviews = ref.watch(dueReviewCountProvider);
    final recommendedPoem = ref.watch(dailyRecommendedPoemProvider);
    final theme = Theme.of(context);

    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;
    final content = <Widget>[
      _buildDailyGoal(context, ref),
      const SizedBox(height: SpacingTokens.lg),
      const PracticeResumeSection(),
      const TodayPlanSection(),

      Text(
        '累计进步',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: SpacingTokens.sm),
      StatOverviewCard(
        items: [
          StatOverviewItem(value: '$learnedPoems', label: '已学诗词'),
          StatOverviewItem(value: '${stats.mathTotalProblems}', label: '数学做题'),
          StatOverviewItem(value: '${stats.totalStars}', label: '总星星'),
        ],
      ),
      const SizedBox(height: SpacingTokens.lg),

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

      // 底部留白：为底部导航栏预留空间
      const SizedBox(height: 100),
    ];
    var contentIndex = 0;
    final pageOverlayStyle =
        (theme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemStatusBarContrastEnforced: false,
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: pageOverlayStyle,
      child: Scaffold(
        // 背景贴边，前景分别避开安全区。后续实色内容覆盖顶部视差背景。
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: SingleChildScrollView(
            controller: _scroll,
            physics: reduceMotion
                ? const ClampingScrollPhysics()
                : const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeCheckInHeader(
                  scrollController: _scroll,
                  pending: !isCheckedIn,
                  child: _buildStreakCard(
                    context,
                    streak,
                    isCheckedIn,
                    stats,
                    learnedPoems,
                    ref,
                  ),
                ),
                // 覆盖背景时也覆盖它的状态栏样式，避免浅底仍显示白图标。
                AnnotatedRegion<SystemUiOverlayStyle>(
                  value: pageOverlayStyle,
                  child: ColoredCard(
                    color: theme.scaffoldBackgroundColor,
                    backgroundOpacity: 1,
                    borderRadius: BorderRadius.zero,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final child in content)
                            if (child is SizedBox)
                              child
                            else
                              child.animateListItem(
                                context,
                                index: contentIndex++,
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreakCard(
    BuildContext context,
    int streak,
    bool isCheckedIn,
    UserStats stats,
    int learnedPoems,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);
    final colors = HomeCheckInColors(theme);
    final selectedGoals = ref.watch(dailyGoalTypesProvider);
    final pendingGoal = [
      for (final type in DailyGoalActivity.values)
        if (selectedGoals.contains(type)) _dailyGoalStatus(ref, type),
    ].where((goal) => !goal.isComplete).firstOrNull;
    final action = isCheckedIn
        ? Icon(
            Icons.check_circle_rounded,
            size: SpacingTokens.xxl,
            color: colors.foreground,
          )
        : FilledButton.tonal(
            onPressed: () async {
              if (pendingGoal != null) {
                context.go(pendingGoal.route);
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
                    const SnackBar(content: Text('打卡失败，请检查设备存储空间后重试')),
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
                      final names = newlyUnlocked.map((a) => a.title).join('、');
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
              backgroundColor: colors.foreground,
              foregroundColor: colors.base,
            ),
            child: Text(pendingGoal?.action ?? '打卡'),
          );

    final summary = Column(
      key: const ValueKey('home-check-in-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              isCheckedIn ? '今日已打卡 ✓' : '今日待打卡',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.foreground,
              ),
            ),
            _LevelBadge(levelName: stats.levelName, colors: colors),
          ],
        ),
        const SizedBox(height: SpacingTokens.sm),
        Wrap(
          spacing: SpacingTokens.xs,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              '$streak',
              style: theme.textTheme.displaySmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.bold,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: Text(
                '天连续',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.foreground,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final reminder = isCheckedIn ? action : HomeCheckInReminder(child: action);
    // 顶部始终铺满页面，前景宽度扣除安全区和共享背景的左右留白。
    // 不在前景放 LayoutBuilder，避免手势帧重新布局时钳制滚动偏移。
    final media = MediaQuery.of(context);
    final contentWidth =
        media.size.width - media.padding.horizontal - SpacingTokens.lg * 2;
    final textScale = media.textScaler.scale(16) / 16;
    final effectiveWidth = contentWidth / textScale;
    if (effectiveWidth >= ResponsiveLayout.mediumBreakpoint ||
        textScale <= 1.25) {
      return Row(
        key: const ValueKey('home-check-in-content'),
        children: [
          Expanded(child: summary),
          const SizedBox(width: SpacingTokens.lg),
          reminder,
        ],
      );
    }
    return Column(
      key: const ValueKey('home-check-in-content'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary,
        const SizedBox(height: SpacingTokens.md),
        Align(alignment: Alignment.center, child: reminder),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, int mistakeCount) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

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
            color: primary,
            onTap: () => context.go(AppRoutes.mathTab),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: _QuickActionButton(
            icon: Icons.functions_rounded,
            label: '查公式',
            color: primary,
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
                  color: primary,
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
                      style: TextStyle(
                        color: theme.colorScheme.onError,
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
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: poem.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const WidgetSpan(
                        child: SizedBox(width: SpacingTokens.sm),
                      ),
                      TextSpan(
                        text: '${poem.dynasty} · ${poem.author}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildDailyGoal(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedGoals = ref.watch(dailyGoalTypesProvider);
    final goals = [
      for (final type in DailyGoalActivity.values)
        if (selectedGoals.contains(type)) _dailyGoalStatus(ref, type),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '今日学习目标 · 完成后可打卡',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        ResponsiveCardGrid(
          children: [
            for (final goal in goals)
              AppTile(
                icon: goal.isComplete ? Icons.check_circle_outline : goal.icon,
                iconColor: theme.colorScheme.primary,
                title: goal.title,
                subtitle: goal.isComplete
                    ? '目标已完成'
                    : '还差 ${goal.goal - goal.count} ${goal.unit} · ${goal.action}',
                onTap: goal.isComplete ? null : () => context.go(goal.route),
                trailing: goal.isComplete ? const SizedBox.shrink() : null,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: SpacingTokens.xs),
          child: Text(
            '今日练习清单提供额外复习建议，不影响打卡目标。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  _DailyGoalStatus _dailyGoalStatus(WidgetRef ref, DailyGoalActivity type) {
    return switch (type) {
      DailyGoalActivity.poem => _DailyGoalStatus(
        type: type,
        count: ref.watch(todayPoemCountProvider),
        goal: ref.watch(dailyPoemGoalProvider),
        unit: '首',
        icon: Icons.menu_book_outlined,
        action: '去学诗词',
        route: AppRoutes.poemTab,
      ),
      DailyGoalActivity.math => _DailyGoalStatus(
        type: type,
        count: ref.watch(todayMathCountProvider),
        goal: ref.watch(dailyMathGoalProvider),
        unit: '题',
        icon: Icons.calculate_outlined,
        action: '去练口算',
        route: AppRoutes.mathTab,
      ),
      DailyGoalActivity.textbookRecognition => _DailyGoalStatus(
        type: type,
        count: ref
            .watch(todayLearningActivityCountsProvider)
            .textbookRecognition,
        goal: 1,
        unit: '次',
        icon: Icons.spellcheck_rounded,
        action: '去认一认',
        route: AppRoutes.chineseSectionOf('textbook'),
      ),
      DailyGoalActivity.textbookWriting => _DailyGoalStatus(
        type: type,
        count: ref.watch(todayLearningActivityCountsProvider).textbookWriting,
        goal: 1,
        unit: '次',
        icon: Icons.gesture_rounded,
        action: '去写一写',
        route: AppRoutes.chineseSectionOf('textbook'),
      ),
      DailyGoalActivity.pictureStoryExpression => _DailyGoalStatus(
        type: type,
        count: ref
            .watch(todayLearningActivityCountsProvider)
            .pictureStoryExpression,
        goal: 1,
        unit: '次',
        icon: Icons.record_voice_over_outlined,
        action: '去看图表达',
        route: AppRoutes.chineseSectionOf('expression'),
      ),
    };
  }
}

class _DailyGoalStatus {
  const _DailyGoalStatus({
    required this.type,
    required this.count,
    required this.goal,
    required this.unit,
    required this.icon,
    required this.action,
    required this.route,
  });

  final DailyGoalActivity type;
  final int count;
  final int goal;
  final String unit;
  final IconData icon;
  final String action;
  final String route;

  bool get isComplete => count >= goal;
  String get title => '${type.label} $count/$goal $unit';
}

/// 等级徽章：`⭐ 童生`。
///
/// 与打卡操作共用实色前景/背景组合，避免光晕改变徽章文字对比度。
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.levelName, required this.colors});

  final String levelName;
  final HomeCheckInColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: SpacingTokens.xs,
      ),
      decoration: BoxDecoration(
        color: colors.foreground,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stars_rounded, size: 14, color: colors.base),
          const SizedBox(width: 4),
          Text(
            levelName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.base,
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
