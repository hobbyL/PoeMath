// lib/features/poem/poem_recite_mode_page.dart
//
// 背诵模式选择页：展示诗词元信息 + 3 种模式卡片 + 诗文预览折叠区。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class PoemReciteModePage extends ConsumerWidget {
  const PoemReciteModePage({super.key, required this.poemId});

  final String poemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poem = ref.watch(poemByIdProvider(poemId));
    final theme = Theme.of(context);

    if (poem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('选择模式')),
        body: const Center(child: Text('诗词未找到')),
      );
    }

    final gradeText = poem.grade != null ? '${poem.grade}年级' : '';
    final diffText = '难度 ${'★' * poem.difficulty}';

    return Scaffold(
      appBar: AppBar(title: const Text('选择练习模式')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部：诗词元信息
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                children: [
                  Text(
                    poem.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    '〔${poem.dynasty}〕${poem.author}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (gradeText.isNotEmpty) ...[
                    const SizedBox(height: SpacingTokens.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildChip(context, gradeText),
                        const SizedBox(width: SpacingTokens.sm),
                        _buildChip(context, diffText),
                        if (poem.tags.isNotEmpty) ...[
                          const SizedBox(width: SpacingTokens.sm),
                          _buildChip(context, poem.tags.first),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),

            // 中间：3 种模式卡片
            Text(
              '选择练习方式',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            _ModeCard(
              icon: Icons.record_voice_over,
              iconColor: theme.colorScheme.primary,
              title: '渐进背诵',
              subtitle: '从全文显示到逐步遮挡，循序渐进掌握',
              onTap: () {
                context.push(AppRoutes.poemReciteOf(poemId));
              },
            ),
            const SizedBox(height: SpacingTokens.sm),

            _ModeCard(
              icon: Icons.edit_note,
              iconColor: theme.colorScheme.secondary,
              title: '填空测试',
              subtitle: '补全诗句中缺失的文字',
              onTap: () {
                context.push(
                  '${AppRoutes.poemQuizOf(poemId)}?type=fill',
                );
              },
            ),
            const SizedBox(height: SpacingTokens.sm),

            _ModeCard(
              icon: Icons.checklist,
              iconColor: theme.colorScheme.tertiary,
              title: '选择题',
              subtitle: '根据上句选择正确的下句、选作者、选朝代',
              onTap: () {
                context.push(
                  '${AppRoutes.poemQuizOf(poemId)}?type=choice',
                );
              },
            ),
            const SizedBox(height: SpacingTokens.lg),

            // 底部：诗文预览折叠区
            ColoredCard(
              color: theme.colorScheme.primary,
              backgroundOpacity: 0.06,
              width: double.infinity,
              padding: EdgeInsets.zero,
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                  ),
                  childrenPadding: const EdgeInsets.only(
                    left: SpacingTokens.md,
                    right: SpacingTokens.md,
                    bottom: SpacingTokens.md,
                  ),
                  leading: Icon(
                    Icons.menu_book_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    '诗文预览',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    Text(
                      poem.content,
                      style: theme.extension<PoemThemeExt>()?.poemContent ??
                          theme.textTheme.bodyMedium?.copyWith(
                            height: 2,
                            letterSpacing: 1.5,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 学习贴士
            ColoredCard(
              color: theme.colorScheme.secondary,
              backgroundOpacity: 0.08,
              width: double.infinity,
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(
                    child: Text(
                      '建议先用「渐进背诵」打基础，再通过「填空」和「选择题」检验记忆效果',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 模式选择卡片。
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppTile(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}
