// lib/features/profile/achievement_page.dart
//
// 层级：features/profile
// 职责：成就勋章列表页 — 按类别展示所有成就，含进度和解锁状态。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/domain/achievement_checker.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

class AchievementPage extends ConsumerWidget {
  const AchievementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(achievementRepoProvider);
    final allDefs = AchievementDefinitions.all;

    // 按 category 分组
    final categories = <String, List<AchievementDef>>{};
    for (final def in allDefs) {
      categories.putIfAbsent(def.category, () => []).add(def);
    }

    // 统计
    final unlockedCount = repo.unlockedCount;
    final totalCount = allDefs.length;

    return Scaffold(
      appBar: AppBar(title: const Text('成就勋章')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            // 总览卡片
            ColoredCard(
              color: theme.semantic.caution,
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    size: 40,
                    color: theme.semantic.caution,
                  ),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已解锁 $unlockedCount / $totalCount',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: SpacingTokens.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            SpacingTokens.radiusSmall,
                          ),
                          child: LinearProgressIndicator(
                            value: totalCount > 0
                                ? unlockedCount / totalCount
                                : 0,
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            color: theme.semantic.caution,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(
                  begin: 0.1,
                  end: 0,
                  duration: 400.ms,
                ),
            const SizedBox(height: SpacingTokens.lg),

            // 按类别展示
            ...categories.entries.indexed.expand((entry) {
              final (idx, mapEntry) = entry;
              final category = mapEntry.key;
              final defs = mapEntry.value;
              return [
                if (idx > 0) const SizedBox(height: SpacingTokens.md),
                _CategorySection(
                  category: category,
                  defs: defs,
                  repo: repo,
                ),
              ];
            }),
          ],
        ),
      ),
    );
  }
}

/// 单个类别分区。
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.defs,
    required this.repo,
  });

  final String category;
  final List<AchievementDef> defs;
  final AchievementRepository repo;

  static const _categoryIcons = <String, IconData>{
    '打卡': Icons.local_fire_department_rounded,
    '诗词': Icons.menu_book_rounded,
    '复习': Icons.refresh_rounded,
    '口算': Icons.calculate_rounded,
    '错题': Icons.auto_fix_high_rounded,
    '公式': Icons.functions_rounded,
    '星星': Icons.star_rounded,
  };

  static const _categoryColors = <String, String>{
    '打卡': 'primary',
    '诗词': 'tertiary',
    '复习': 'secondary',
    '口算': 'primary',
    '错题': 'secondary',
    '公式': 'tertiary',
    '星星': 'primary',
  };

  Color _colorFor(String category, ThemeData theme) {
    return switch (_categoryColors[category]) {
      'tertiary' => theme.colorScheme.tertiary,
      'secondary' => theme.colorScheme.secondary,
      _ => theme.colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorFor(category, theme);
    final icon = _categoryIcons[category] ?? Icons.emoji_events_rounded;

    // 该类别解锁数
    final unlockedInCategory = defs.where((d) {
      final a = repo.getById(d.id);
      return a != null && a.isUnlocked;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 类别标题
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: SpacingTokens.sm),
            Text(
              category,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const Spacer(),
            Text(
              '$unlockedInCategory / ${defs.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.sm),

        // 成就列表
        ...defs.indexed.map((entry) {
          final (idx, def) = entry;
          final achievement = repo.getById(def.id);
          return _AchievementTile(
            def: def,
            achievement: achievement,
            color: color,
          )
              .animate()
              .fadeIn(delay: (60 * idx).ms, duration: 300.ms)
              .slideX(
                begin: 0.08,
                end: 0,
                delay: (60 * idx).ms,
                duration: 300.ms,
              );
        }),
      ],
    );
  }
}

/// 单个成就条目。
class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    required this.def,
    required this.achievement,
    required this.color,
  });

  final AchievementDef def;
  final Achievement? achievement;
  final Color color;

  static const _iconMap = <String, IconData>{
    'trophy': Icons.emoji_events_rounded,
    'fire': Icons.local_fire_department_rounded,
    'book': Icons.menu_book_rounded,
    'star': Icons.star_rounded,
    'crown': Icons.workspace_premium_rounded,
    'calculator': Icons.calculate_rounded,
    'target': Icons.track_changes_rounded,
    'check_all': Icons.done_all_rounded,
    'bolt': Icons.bolt_rounded,
    'flame': Icons.whatshot_rounded,
    'repair': Icons.auto_fix_high_rounded,
    'refresh': Icons.refresh_rounded,
    'function': Icons.functions_rounded,
    'medal': Icons.military_tech_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnlocked = achievement?.isUnlocked ?? false;
    final progress = achievement?.progress ?? 0.0;
    final progressPct = (progress * 100).toInt();
    final icon = _iconMap[def.iconName] ?? Icons.emoji_events_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: ColoredCard(
        color: isUnlocked ? color : theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Row(
          children: [
            // 图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isUnlocked
                    ? color.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(
                  SpacingTokens.radiusMedium,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 24,
                color: isUnlocked
                    ? color
                    : theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: SpacingTokens.md),

            // 标题 + 描述 + 进度条
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          def.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isUnlocked
                                ? null
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (isUnlocked)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: color,
                        )
                      else
                        Text(
                          '$progressPct%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    def.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!isUnlocked && progress > 0) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        SpacingTokens.radiusSmall,
                      ),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: color.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  if (isUnlocked && achievement?.unlockedAt != null) ...[
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      _formatDate(achievement!.unlockedAt!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}/${d.month}/${d.day} 解锁';
  }
}
