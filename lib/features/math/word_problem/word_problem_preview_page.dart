// lib/features/math/word_problem/word_problem_preview_page.dart
//
// 层级：features/math/word_problem
// 职责：家长预览页 —— 展示 LLM 草稿与本地校验结果，通过项默认全选，
//       家长确认后入库（batchId 此刻落定）；不自动补生成被丢弃的题。
//
// 布局约定：概要统计卡与底部整宽按钮不展示——确认按钮收敛到 AppBar 右上角
//（窄屏图标 / 宽屏图标+「确认入库 N 题」，与全 App 响应式 AppBar 按钮一致）；
// 题卡内勾选框靠右，「解题讲解」展开按钮跟在算式行尾。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// 单题预览项：skeleton（本地可信）+ draft（LLM 输出）+ 校验结论。
class WordProblemPreviewItem {
  const WordProblemPreviewItem({
    required this.skeleton,
    required this.draft,
    required this.rejectReason,
  });

  final ProblemSkeleton skeleton;

  /// LLM 草稿；null = LLM 未返回该题。
  final LlmWordProblemDraft? draft;

  /// 校验违规原因；null = 通过校验。
  final String? rejectReason;

  bool get accepted => rejectReason == null && draft != null;
}

/// 预览页数据（生成页 → 预览页 extra 传参）。
class WordProblemPreviewData {
  const WordProblemPreviewData({
    required this.grade,
    required this.semester,
    required this.topicName,
    required this.items,
  });

  final int grade;
  final String semester;
  final String topicName;
  final List<WordProblemPreviewItem> items;
}

class WordProblemPreviewPage extends ConsumerStatefulWidget {
  const WordProblemPreviewPage({super.key, required this.data});

  final WordProblemPreviewData data;

  @override
  ConsumerState<WordProblemPreviewPage> createState() =>
      _WordProblemPreviewPageState();
}

class _WordProblemPreviewPageState
    extends ConsumerState<WordProblemPreviewPage> {
  /// 通过校验的题的勾选状态（默认全选）。
  late final Map<int, bool> _selected;

  /// 讲解展开状态。
  final Map<int, bool> _explanationExpanded = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (var i = 0; i < widget.data.items.length; i++)
        if (widget.data.items[i].accepted) i: true,
    };
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  Future<void> _confirm() async {
    if (_saving || _selectedCount == 0) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    // 用微秒时间戳：同毫秒连续确认两批会合并批次，按批删除/筛选混淆。
    // 与下方 id（已用微秒）保持一致；存量毫秒 batchId 天然是不同 key，无需迁移。
    final batchId = now.microsecondsSinceEpoch.toString();
    final profileId = ProfileScope.currentId;

    final problems = <LlmProblem>[];
    var seq = 0;
    for (var i = 0; i < widget.data.items.length; i++) {
      final item = widget.data.items[i];
      if (!item.accepted || !(_selected[i] ?? false)) continue;
      problems.add(
        LlmProblem(
          id: '${now.microsecondsSinceEpoch}_${seq++}',
          profileId: profileId,
          questionText: item.draft!.text,
          unit: item.skeleton.unitHint,
          operands: item.skeleton.operands,
          operators: [
            for (final op in item.skeleton.operators) op.symbol,
          ],
          answer: item.skeleton.answer,
          explanation: item.draft!.explanation,
          batchId: batchId,
          createdAt: now,
          grade: widget.data.grade,
          semester: widget.data.semester,
          topic: widget.data.topicName,
          difficulty: item.skeleton.difficulty,
        ),
      );
    }

    try {
      await ref.read(llmProblemRepositoryProvider).addAll(problems);
    } on Object catch (_) {
      // addAll 是 Hive 循环 put、不吞异常（磁盘满/Box 损坏会抛出）：
      // 不加防护时 _saving 永久为 true，确认按钮永久禁用。
      // Hive 无事务：部分写入不回滚，重试会以新 id 重新入库（接受该取舍）。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('入库失败，请重试')),
        );
        setState(() => _saving = false);
      }
      return;
    }
    ref.read(llmLibraryVersionProvider.notifier).state++;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已入库 $_selectedCount 题')),
    );
    // 入库后跳题库页，替换预览页避免返回时重复入库。
    context.pushReplacement(AppRoutes.wordProblemLibrary);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.data.items;

    // 布局约定：概要卡片与底部整宽按钮已移除——确认按钮收敛到 AppBar
    // 右上角（窄屏图标 / 宽屏图标+文案），题目列表占满正文。
    final isWide = MediaQuery.sizeOf(context).width >= 420;
    final confirmLabel = '确认入库 $_selectedCount 题';

    return Scaffold(
      appBar: AppBar(
        title: const Text('家长预览'),
        actions: [
          if (isWide)
            TextButton.icon(
              onPressed: _saving || _selectedCount == 0 ? null : _confirm,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.library_add_check_outlined,
                      size: 18,
                    ),
              label: Text(confirmLabel),
            )
          else
            IconButton(
              onPressed: _saving || _selectedCount == 0 ? null : _confirm,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.library_add_check_outlined,
                      size: 18,
                    ),
              tooltip: confirmLabel,
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(SpacingTokens.md),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: _buildItemCard(context, index: index, item: items[index]),
          );
        },
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context, {
    required int index,
    required WordProblemPreviewItem item,
  }) {
    final theme = Theme.of(context);
    final skeleton = item.skeleton;
    // 骨架自带算式组装（"12 + 4"），此处仅拼答案与单位。
    final expressionText =
        '${skeleton.expressionText} = ${skeleton.answer}';

    if (!item.accepted) {
      // 被丢弃的题：置灰显示原因
      return ColoredCard(
        color: theme.colorScheme.outline,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: SpacingTokens.xs),
                Text(
                  '已丢弃',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.xs),
            if (item.draft != null) ...[
              Text(
                item.draft!.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SpacingTokens.xs),
            ],
            Text(
              '算式：$expressionText${skeleton.unitHint}\n'
              '丢弃原因：${item.rejectReason}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.semantic.caution,
              ),
            ),
          ],
        ),
      );
    }

    final draft = item.draft!;
    final expanded = _explanationExpanded[index] ?? false;
    return ColoredCard(
      color: theme.colorScheme.primary,
      width: double.infinity,
      onTap: () => setState(() => _selected[index] = !(_selected[index] ?? true)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  draft.text,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              // 勾选框靠右：整卡可点切换，勾选框本体也响应。
              Checkbox(
                value: _selected[index] ?? true,
                onChanged: (value) =>
                    setState(() => _selected[index] = value ?? false),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  '算式：$expressionText${skeleton.unitHint}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 「解题讲解」展开按钮跟在算式行尾（explanation 为空则无此按钮）。
              if (draft.explanation.trim().isNotEmpty)
                _InlineIconButton(
                  icon: expanded ? Icons.expand_less : Icons.expand_more,
                  label: expanded ? '收起讲解' : '解题讲解',
                  onPressed: () => setState(
                    () => _explanationExpanded[index] = !expanded,
                  ),
                ),
            ],
          ),
          if (draft.explanation.trim().isNotEmpty && expanded) ...[
            const SizedBox(height: SpacingTokens.xs),
            Text(
              draft.explanation,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// 算式行尾的紧凑讲解展开按钮：无按钮水波纹占位感，视觉近似文字链接。
class _InlineIconButton extends StatelessWidget {
  const _InlineIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.xs,
          vertical: SpacingTokens.xs / 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
