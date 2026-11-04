// lib/features/math/word_problem/word_problem_library_page.dart
//
// 层级：features/math/word_problem
// 职责：应用题题库管理 —— 统计卡、筛选、批次分组列表、
//       单题/按批/清空删除（二次确认）、开始练习。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class WordProblemLibraryPage extends ConsumerStatefulWidget {
  const WordProblemLibraryPage({super.key});

  @override
  ConsumerState<WordProblemLibraryPage> createState() =>
      _WordProblemLibraryPageState();
}

class _WordProblemLibraryPageState
    extends ConsumerState<WordProblemLibraryPage> {
  String? _reviewLabel(LlmProblem problem) {
    if (problem.generationMetadataJson.isEmpty) return '旧版题目 · 请核对题意';
    try {
      if (WordProblemMetadata.decode(problem.generationMetadataJson) == null) {
        return '题目版本暂不支持校验 · 请核对题意';
      }
    } on FormatException {
      return '题意信息无法校验 · 请核对题意';
    }
    return null;
  }

  /// 筛选状态；null = 不过滤。
  WordProblemTopic? _topicFilter;
  bool? _doneFilter;
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
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
      batches
          .putIfAbsent(problem.batchId, () {
            batchOrder.add(problem.batchId);
            return <LlmProblem>[];
          })
          .add(problem);
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
          // 筛选入口：有题目时才出现；选中任一筛选条件时图标高亮（实心）。
          if (all.isNotEmpty)
            IconButton(
              onPressed: _openFilterSheet,
              icon: Icon(
                _topicFilter != null || _doneFilter != null
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
              ),
              tooltip: '筛选',
            ),
        ],
      ),
      body: all.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                // 统计卡（与口算练习页统计卡同款：共用 StatOverviewCard）。
                // 卡片自身不带外边距（见组件注释），本页 Column 无横向
                // padding，这里补上与下方列表一致的 md。
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: StatOverviewCard(
                    items: [
                      StatOverviewItem(value: '${stats.total}', label: '总题数'),
                      StatOverviewItem(value: '${stats.done}', label: '已做'),
                      StatOverviewItem(
                        value: '${(stats.accuracy * 100).toStringAsFixed(0)}%',
                        label: '正确率',
                      ),
                    ],
                  ),
                ),

                // 批次分组列表
                Expanded(
                  child: filtered.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.filter_alt_outlined,
                          title: '当前筛选无题目',
                          description: '试试其他题型或完成状态。',
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
                        label: Text('开始练习 · ${filtered.length} 题'),
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    OutlinedButton.icon(
                      onPressed: _deleting ? null : () => _clearAll(context),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// 打开筛选弹窗：知识点 + 做题状态，实时应用到列表，「完成」关闭。
  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // 内容按内容高度自适应；isScrollControlled 解除默认 9/16 高度上限，
      // 避免知识点 Chip 换行后在矮屏/测试面上溢出（RenderFlex overflow）。
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final labelStyle = theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void apply(VoidCallback fn) {
              setState(fn);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('知识点', style: labelStyle),
                    const SizedBox(height: SpacingTokens.xs),
                    Wrap(
                      spacing: SpacingTokens.xs,
                      runSpacing: SpacingTokens.xs,
                      children: [
                        for (final topic in WordProblemTopic.values)
                          FilterChip(
                            label: Text(topic.label),
                            selected: _topicFilter == topic,
                            onSelected: (s) =>
                                apply(() => _topicFilter = s ? topic : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Text('状态', style: labelStyle),
                    const SizedBox(height: SpacingTokens.xs),
                    Wrap(
                      spacing: SpacingTokens.xs,
                      children: [
                        FilterChip(
                          label: const Text('未做'),
                          selected: _doneFilter == false,
                          onSelected: (s) =>
                              apply(() => _doneFilter = s ? false : null),
                        ),
                        FilterChip(
                          label: const Text('已做'),
                          selected: _doneFilter == true,
                          onSelected: (s) =>
                              apply(() => _doneFilter = s ? true : null),
                        ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.lg),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _topicFilter == null && _doneFilter == null
                              ? null
                              : () => apply(() {
                                  _topicFilter = null;
                                  _doneFilter = null;
                                }),
                          child: const Text('重置'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) => AppEmptyState(
    icon: Icons.auto_awesome_outlined,
    title: '题库还是空的',
    description: '去生成一批应用题，家长确认后即可练习',
    actions: [
      FilledButton.icon(
        onPressed: () => context.push(AppRoutes.wordProblemGenerate),
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('去生成'),
      ),
    ],
  );

  Widget _buildBatchSection(
    BuildContext context,
    String batchId,
    List<LlmProblem> problems,
  ) {
    final theme = Theme.of(context);
    final first = problems.first;
    final topicLabel = problems
        .map(
          (problem) =>
              WordProblemTopic.tryParse(problem.topic)?.label ?? problem.topic,
        )
        .toSet()
        .join('、');

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${first.grade} 年级${first.semester}学期 · $topicLabel · '
                    '共 ${problems.length} 题 · ${_formatDate(first.createdAt)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: '删除该批次',
                  onPressed: _deleting
                      ? null
                      : () => _deleteBatch(context, batchId),
                ),
              ],
            ),
          ),
          for (final problem in problems)
            Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              // 点击卡片 → 单题练习；删除按钮内置于卡片右侧。
              // 该行需「正文可点击 + 卡内操作按钮 + 无前置图标」，超出 AppTile
              // 契约（trailing 非空即禁用 onTap、且图标必填），故直接用
              // ColoredCard（AppTile 的同款基底）组合。
              child: ColoredCard(
                color: theme.colorScheme.primary,
                onTap: () => _startPractice([problem]),
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.md,
                  SpacingTokens.sm,
                  SpacingTokens.sm,
                  SpacingTokens.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            problem.questionText,
                            // 按可用宽度截断：宽屏能放下更多字，
                            // 只有真放不下才出省略号（替代旧的 24 字硬切）。
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_reviewLabel(problem) != null) ...[
                            const SizedBox(height: SpacingTokens.xs),
                            Text(
                              _reviewLabel(problem)!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (problem.done) ...[
                            const SizedBox(height: 2),
                            Text(
                              '已做 ${problem.attempts} 次 · 答对 ${problem.correctCount} 次',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      tooltip: '删除此题',
                      onPressed: _deleting
                          ? null
                          : () => _confirmDelete(context, problem),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}月${date.day}日';
  }

  void _startPractice(List<LlmProblem> problems) {
    // 未做的题排在前面（已做的押后），整体仍保持创建时间倒序稳定性。
    final sorted = [...problems]
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return 0;
      });
    context.push(AppRoutes.wordProblemPractice, extra: sorted);
  }

  Future<void> _confirmDelete(BuildContext context, LlmProblem problem) {
    final repo = ref.read(llmProblemRepositoryProvider);
    return _deleteWithParentVerification(
      context,
      title: '删除该题',
      content: problem.questionText,
      delete: (authorize) => repo.delete(problem.id, authorize: authorize),
    );
  }

  Future<void> _deleteBatch(BuildContext context, String batchId) {
    final repo = ref.read(llmProblemRepositoryProvider);
    final count = repo
        .getAll()
        .where((problem) => problem.batchId == batchId)
        .length;
    return _deleteWithParentVerification(
      context,
      title: '删除该批次',
      content: '将删除该批次的 $count 道应用题，含做题记录，不可恢复。',
      delete: (authorize) => repo.deleteBatch(batchId, authorize: authorize),
    );
  }

  Future<void> _clearAll(BuildContext context) {
    final repo = ref.read(llmProblemRepositoryProvider);
    return _deleteWithParentVerification(
      context,
      title: '清空题库',
      content: '将删除全部应用题及其做题记录，不可恢复。',
      confirmLabel: '清空',
      delete: (authorize) => repo.clearAll(authorize: authorize),
    );
  }

  Future<void> _deleteWithParentVerification(
    BuildContext context, {
    required String title,
    required String content,
    required Future<void> Function(VoidCallback authorize) delete,
    String confirmLabel = '删除',
  }) async {
    if (_deleting) return;
    setState(() => _deleting = true);
    final revision = ProfileScope.revision;
    var deletionStarted = false;
    void authorize() {
      assertParentAccess(context);
      if (ProfileScope.revision != revision) throw const ParentAccessDenied();
    }

    try {
      if (!await ensureParentAccess(context) || !context.mounted) return;
      authorize();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: confirmLabel == '清空'
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(dialogContext)
                          .colorScheme
                          .error,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      authorize();
      deletionStarted = true;
      await delete(authorize);
    } on ParentAccessDenied {
      _showDeleteError('家长验证已失效，删除已停止，请重新验证');
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '$title失败',
        tag: 'WordProblemLibrary',
        error: error,
        stackTrace: stackTrace,
      );
      _showDeleteError('删除未完成，请重试');
    } finally {
      if (mounted) {
        // 批量删除中途停止也刷新，显示已经完成的删除结果。
        if (deletionStarted) {
          ref.read(llmLibraryVersionProvider.notifier).state++;
        }
        setState(() => _deleting = false);
      }
    }
  }

  void _showDeleteError(String message) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
