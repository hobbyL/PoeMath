// lib/features/poem/poem_learning_path_page.dart
//
// 层级：features/poem
// 职责：诗词学习路径 — 按年级分阶段展示学习进度，激励用户完成每个阶段。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class PoemLearningPathPage extends ConsumerWidget {
  const PoemLearningPathPage({super.key});

  static const _gradeIcons = <int, IconData>{
    1: Icons.looks_one_rounded,
    2: Icons.looks_two_rounded,
    3: Icons.looks_3_rounded,
    4: Icons.looks_4_rounded,
    5: Icons.looks_5_rounded,
    6: Icons.looks_6_rounded,
  };

  static const _gradeLabels = <int, String>{
    1: '一年级',
    2: '二年级',
    3: '三年级',
    4: '四年级',
    5: '五年级',
    6: '六年级',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final poemRepo = ref.watch(poemRepoProvider);
    final progressRepo = ref.watch(poemProgressRepoProvider);
    final grades = ref.watch(availableGradesProvider);

    // 计算各年级进度
    final gradeStats = <int, _GradeProgress>{};
    for (final grade in grades) {
      final poems = poemRepo.byGrade(grade);
      var learned = 0;
      var mastered = 0;
      for (final poem in poems) {
        final progress = progressRepo.get(poem.id);
        if (progress != null) {
          if (progress.status == LearningStatus.mastered) {
            mastered++;
            learned++;
          } else if (progress.status != LearningStatus.notStarted) {
            learned++;
          }
        }
      }
      gradeStats[grade] = _GradeProgress(
        total: poems.length,
        learned: learned,
        mastered: mastered,
      );
    }

    // 总进度
    final totalPoems = gradeStats.values.fold<int>(0, (s, g) => s + g.total);
    final totalLearned =
        gradeStats.values.fold<int>(0, (s, g) => s + g.learned);
    final totalMastered =
        gradeStats.values.fold<int>(0, (s, g) => s + g.mastered);

    return Scaffold(
      appBar: AppBar(title: const Text('学习路径')),
      body: SafeArea(
        child: AnimatedPageBody(
          children: [
            // 总进度卡片
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.route_rounded,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Text(
                        '课标古诗词学习进度',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  // 总进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      SpacingTokens.radiusSmall,
                    ),
                    child: LinearProgressIndicator(
                      value: totalPoems > 0 ? totalLearned / totalPoems : 0,
                      minHeight: 10,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '已学 $totalLearned / $totalPoems 首',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '已掌握 $totalMastered 首',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.semantic.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 各年级进度
            ...grades.asMap().entries.map((entry) {
              final index = entry.key;
              final grade = entry.value;
              final stats = gradeStats[grade]!;
              final isUnlocked = _isUnlocked(grade, grades, gradeStats);

              return Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                child: _GradeStageCard(
                  grade: grade,
                  icon: _gradeIcons[grade] ?? Icons.school,
                  label: _gradeLabels[grade] ?? '$grade 年级',
                  stats: stats,
                  isUnlocked: isUnlocked,
                  onTap: isUnlocked
                      ? () {
                          // 跳转到诗词列表，筛选该年级
                          ref.read(selectedGradeProvider.notifier).state =
                              grade;
                          Navigator.of(context).pop();
                        }
                      : null,
                )
                    .animate()
                    .fadeIn(
                      delay: (100 * index).ms,
                      duration: 400.ms,
                    )
                    .slideX(
                      begin: 0.05,
                      end: 0,
                      delay: (100 * index).ms,
                      duration: 400.ms,
                    ),
              );
            }),
            const SizedBox(height: SpacingTokens.lg),
          ],
        ),
      ),
    );
  }

  /// 阶段解锁规则：前一个年级学习了 50% 以上即解锁
  bool _isUnlocked(
    int grade,
    List<int> grades,
    Map<int, _GradeProgress> stats,
  ) {
    if (grade == grades.first) return true; // 第一个年级始终解锁
    final prevGrade = grades[grades.indexOf(grade) - 1];
    final prev = stats[prevGrade];
    if (prev == null) return false;
    return prev.total == 0 || prev.learned / prev.total >= 0.5;
  }
}

class _GradeProgress {
  final int total;
  final int learned;
  final int mastered;

  const _GradeProgress({
    required this.total,
    required this.learned,
    required this.mastered,
  });

  double get ratio => total > 0 ? learned / total : 0;
  bool get isComplete => learned >= total && total > 0;
}

class _GradeStageCard extends StatelessWidget {
  const _GradeStageCard({
    required this.grade,
    required this.icon,
    required this.label,
    required this.stats,
    required this.isUnlocked,
    this.onTap,
  });

  final int grade;
  final IconData icon;
  final String label;
  final _GradeProgress stats;
  final bool isUnlocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isUnlocked
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return ColoredCard(
      color: color,
      backgroundOpacity: isUnlocked ? 0.08 : 0.04,
      onTap: onTap,
      child: Row(
        children: [
          // 阶段图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(
                SpacingTokens.radiusMedium,
              ),
            ),
            alignment: Alignment.center,
            child: isUnlocked
                ? Icon(icon, size: 28, color: color)
                : Icon(Icons.lock_outline, size: 24, color: color),
          ),
          const SizedBox(width: SpacingTokens.md),

          // 进度信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isUnlocked ? null : color,
                      ),
                    ),
                    const Spacer(),
                    if (stats.isComplete)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.semantic.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            SpacingTokens.radiusPill,
                          ),
                        ),
                        child: Text(
                          '✓ 完成',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.semantic.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Text(
                        '${stats.learned}/${stats.total}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.xs),
                // 进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: stats.ratio,
                    minHeight: 6,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                      stats.isComplete ? theme.semantic.success : color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isUnlocked) ...[
            const SizedBox(width: SpacingTokens.sm),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}
