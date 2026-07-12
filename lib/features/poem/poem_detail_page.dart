// lib/features/poem/poem_detail_page.dart
//
// 诗词详情页：展示全文、拼音、译文、赏析、注释，可收藏和开始背诵。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class PoemDetailPage extends ConsumerWidget {
  const PoemDetailPage({super.key, required this.poemId});

  final String poemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poem = ref.watch(poemByIdProvider(poemId));
    final isFav = ref.watch(isFavoriteProvider(poemId));
    final progress = ref.watch(poemProgressProvider(poemId));
    final theme = Theme.of(context);

    if (poem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('诗词详情')),
        body: const Center(child: Text('诗词未找到')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(poem.title),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? ColorTokens.poemSeal : null,
            ),
            onPressed: () async {
              final repo = ref.read(poemFavoriteRepoProvider);
              await repo.toggle(poemId);
              ref.invalidate(isFavoriteProvider(poemId));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题区
            Center(
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
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),

            // 正文
            _buildSection(
              context,
              child: Center(
                child: Text(
                  poem.content,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 2,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // 拼音
            if (poem.pinyin.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '拼音', poem.pinyin),
            ],

            // 译文
            if (poem.translation.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '译文', poem.translation),
            ],

            // 注释
            if (poem.annotations.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildAnnotations(context, poem),
            ],

            // 赏析
            if (poem.appreciation.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '赏析', poem.appreciation),
            ],

            // 背景
            if (poem.background.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '创作背景', poem.background),
            ],

            // 名句
            if (poem.famousLines.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildFamousLines(context, poem.famousLines),
            ],

            // 学习状态
            if (progress != null) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildProgressInfo(context, progress.studyCount),
            ],

            const SizedBox(height: SpacingTokens.xl),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: FilledButton.icon(
            onPressed: () {
              context.push(AppRoutes.poemReciteOf(poemId));
            },
            icon: const Icon(Icons.record_voice_over),
            label: const Text('开始背诵'),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ColorTokens.poemDivider,
        ),
      ),
      child: child,
    );
  }

  Widget _buildLabeledSection(
    BuildContext context,
    String label,
    String content,
  ) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: ColorTokens.poemGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnotations(BuildContext context, Poem poem) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '注释',
            style: theme.textTheme.titleSmall?.copyWith(
              color: ColorTokens.poemGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          ...poem.annotations.map((ann) {
            return Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ann.word}：',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      ann.meaning,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFamousLines(BuildContext context, List<String> lines) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '名句',
            style: theme.textTheme.titleSmall?.copyWith(
              color: ColorTokens.poemGold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          ...lines.map((line) {
            return Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.format_quote,
                    size: 16,
                    color: ColorTokens.poemGold,
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(
                    child: Text(
                      line,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProgressInfo(BuildContext context, int studyCount) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Row(
        children: [
          const Icon(
            Icons.history,
            size: 18,
            color: ColorTokens.poemGreen,
          ),
          const SizedBox(width: SpacingTokens.sm),
          Text(
            '已学习 $studyCount 次',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
