// lib/features/math/word_problem/word_problem_library_page.dart
//
// 层级：features/math/word_problem
// 职责：应用题题库管理 —— 统计卡、筛选、批次分组列表、
//       单题/按批/清空删除（二次确认）、开始练习。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/models/problem_skeleton.dart';

class WordProblemLibraryPage extends ConsumerStatefulWidget {
  const WordProblemLibraryPage({super.key});

  @override
  ConsumerState<WordProblemLibraryPage> createState() =>
      _WordProblemLibraryPageState();
}

class _WordProblemLibraryPageState
    extends ConsumerState<WordProblemLibraryPage> {
  /// 筛选状态；null = 不过滤。
  WordProblemTopic? _topicFilter;
  bool? _doneFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 420;
    final stats = ref.watch(llmLibraryStatsProvider);
    final all = ref.watch(llmProblemListProvider);

    final filtered = all
        .where((p) => _topicFilter == null || p.topic == _topicFilter!.name)
        .where((p) => _doneFilter == null || p.done == _doneFilter)
        .toList();

    // 按批次分组（保持创建时间倒序）。
    final batchOrder = <String>[];
    final batches = <String, List<LlmProblem>>{};
    for (final problem in filtered) {
      batches.putIfAbsent(problem.batchId, () {
        batchOrder.add(problem.batchId);
        return <LlmProblem>[];
      }).add(problem);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('应用题题库'),
        // 「生成新题」常驻入口：宽屏图标+文案 / 窄屏仅图标（文案进 tooltip），
        // 与全 App 响应式 AppBar 按钮约定一致（阈值 420）。空题库引导态另有大按钮。
        actions: [
          if (isWide)
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.wordProblemGenerate),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('生成新题'),
            )
          else
            IconButton(
              onPressed: () => context.push(AppRoutes.wordProblemGenerate),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              tooltip: '生成新题',
            ),
        ],
      ),
      body: all.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                // 统计卡
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: ColoredCard(
                    color: theme.colorScheme.primary,
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat(
                          context,
                          '${stats.total}',
                          '总题数',
                        ),
                        _buildStat(
                          context,
                          '${stats.done}',
                          '已做',
                        ),
                        _buildStat(
                          context,
                          '${(stats.accuracy * 100).toStringAsFixed(0)}%',
                          '正确率',
                        ),
                      ],
                    ),
                  ),
                ),

                // 筛选 chips
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                  ),
                  child: Wrap(
                    spacing: SpacingTokens.xs,
                    runSpacing: SpacingTokens.xs,
                    children: [
                      for (final topic in WordProblemTopic.values)
                        FilterChip(
                          label: Text(topic.label),
                          selected: _topicFilter == topic,
                          onSelected: (selected) => setState(() {
                            _topicFilter = selected ? topic : null;
                          }),
                        ),
                      FilterChip(
                        label: const Text('未做'),
                        selected: _doneFilter == false,
                        onSelected: (selected) => setState(() {
                          _doneFilter = selected ? false : null;
                        }),
                      ),
                      FilterChip(
                        label: const Text('已做'),
                        selected: _doneFilter == true,
                        onSelected: (selected) => setState(() {
                          _doneFilter = selected ? true : null;
                        }),
                      ),
                    ],
                  ),
                ),

                // 批次分组列表
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            '当前筛选无题目',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(SpacingTokens.md),
                          itemCount: batchOrder.length,
                          itemBuilder: (context, index) {
                            final batchId = batchOrder[index];
                            final problems = batches[batchId]!;
                            return _buildBatchSection(
                              context,
                              batchId,
                              problems,
                            );
                          },
                        ),
                ),
              ],
            ),
      // 底部操作
      bottomNavigationBar: all.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: filtered.isEmpty
                            ? null
                            : () => _startPractice(filtered),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          '开始练习 · ${filtered.length} 题',
                        ),
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    OutlinedButton.icon(
                      onPressed: () => _clearAll(context),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStat(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: SpacingTokens.md),
            Text('题库还是空的', style: theme.textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              '去生成一批应用题，家长确认后即可练习',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.wordProblemGenerate),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('去生成'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchSection(
    BuildContext context,
    String batchId,
    List<LlmProblem> problems,
  ) {
    final theme = Theme.of(context);
    final first = problems.first;
    final topicLabel = WordProblemTopic.tryParse(first.topic)?.label ??
        first.topic;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${first.grade} 年级${first.semester}学期 · $topicLabel · '
                    '批次 ${_formatDate(first.createdAt)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: '删除该批次',
                  onPressed: () => _deleteBatch(context, batchId, problems),
                ),
              ],
            ),
          ),
          for (final problem in problems)
            Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: AppTile(
                icon: problem.done
                    ? Icons.task_alt_outlined
                    : Icons.help_outline_rounded,
                iconColor: problem.done
                    ? theme.semantic.success
                    : theme.colorScheme.primary,
                title: _summarize(problem.questionText),
                subtitle: problem.done
                    ? '已做 ${problem.attempts} 次 · 答对 ${problem.correctCount} 次'
                    : '未做 · ${_formatDate(problem.createdAt)}',
                onTap: () => _confirmDelete(context, problem),
              ),
            ),
        ],
      ),
    );
  }

  String _summarize(String text) {
    return text.length > 24 ? '${text.substring(0, 24)}…' : text;
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  void _startPractice(List<LlmProblem> problems) {
    // 未做的题排在前面（已做的押后），整体仍保持创建时间倒序稳定性。
    final sorted = [...problems]..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return 0;
      });
    context.push(AppRoutes.wordProblemPractice, extra: sorted);
  }

  Future<void> _confirmDelete(BuildContext context, LlmProblem problem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除该题'),
        content: Text(problem.questionText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(llmProblemRepositoryProvider).delete(problem.id);
    ref.read(llmLibraryVersionProvider.notifier).state++;
  }

  Future<void> _deleteBatch(
    BuildContext context,
    String batchId,
    List<LlmProblem> problems,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除该批次'),
        content: Text('将删除该批次的 ${problems.length} 道应用题，'
            '含做题记录，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(llmProblemRepositoryProvider).deleteBatch(batchId);
    ref.read(llmLibraryVersionProvider.notifier).state++;
  }

  Future<void> _clearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空题库'),
        content: const Text('将删除全部应用题及其做题记录，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(llmProblemRepositoryProvider).clearAll();
    ref.read(llmLibraryVersionProvider.notifier).state++;
  }
}
