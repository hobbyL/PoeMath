// lib/features/math/math_mistake_detail_page.dart
//
// 层级：features/math
// 职责：错题详情页 — 展示错题完整信息、解题步骤和操作按钮。
//       同时服务于错题本列表和练习记录详情的导航入口。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/mistake_consolidation_labels.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/math_ai_explain_sheet.dart';
import 'package:poemath/features/math/widgets/math_text.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/math_mistake_snapshot.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';

class MathMistakeDetailPage extends ConsumerWidget {
  const MathMistakeDetailPage({super.key, required this.mistakeId});

  /// 错题 ID，用于从仓库实时读取最新状态。
  final String mistakeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(mathMistakeRepoProvider);
    final mistake = repo.getById(mistakeId);

    if (mistake == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错题详情')),
        body: const Center(child: Text('该错题已被删除')),
      );
    }

    final problem = mistake.originalProblem;
    final attempt = mistake.originalAttempt;
    final isWide = MediaQuery.sizeOf(context).width >= 420;
    // AI 解析入口（移至 AppBar 右上角）：只做讲解展示，不参与判分与错题状态。
    void openAiExplain() => showMathAiExplainSheet(
          context,
          problemText: mistake.problemText,
          correctAnswer: mistake.correctAnswer,
          userAnswer: mistake.userAnswer,
          diagnosisCategory: mistake.errorType,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题详情'),
        actions: [
          if (isWide)
            TextButton.icon(
              onPressed: openAiExplain,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('AI 帮我讲'),
            )
          else
            IconButton(
              onPressed: openAiExplain,
              // 与宽屏按钮同尺寸（18）：默认 24 的实心图标在仅图标态下偏大。
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              tooltip: 'AI 帮我讲',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 题目卡片
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 题目文本
                  MathText(
                    mistake.problemText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),

                  // 答案对比行
                  Row(
                    children: [
                      _AnswerChip(
                        label: '你的答案',
                        value: mistake.userAnswer,
                        color: theme.colorScheme.error,
                        icon: Icons.cancel_rounded,
                      ),
                      const SizedBox(width: SpacingTokens.lg),
                      _AnswerChip(
                        label: '正确答案',
                        value: mistake.correctAnswer,
                        color: theme.semantic.success,
                        icon: Icons.check_circle_rounded,
                      ),
                    ],
                  ),

                  if (problem != null && VerticalAttempt.supports(problem)) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    const Text('重练时只需填写结果各数位，进位或借位无需填写。'),
                    if (attempt != null)
                      Text(
                        [
                          for (final (field, title)
                              in VerticalAttempt.fieldsFor(problem))
                            '$title：${attempt.field(field)}',
                          if (attempt.regroup.isNotEmpty)
                            '历史${problem.operators.single == Operator.add ? '个位进位' : '十位借位'}：${attempt.regroup}',
                        ].join(' · '),
                      ),
                  ],

                  // 已掌握标记
                  if (mistake.isResolved) ...[
                    const SizedBox(height: SpacingTokens.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.sm,
                        vertical: SpacingTokens.xs,
                      ),
                      decoration: BoxDecoration(
                        color: theme.semantic.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          SpacingTokens.radiusSmall,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: theme.semantic.success,
                          ),
                          const SizedBox(width: SpacingTokens.xs),
                          Text(
                            '已掌握',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.semantic.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (mistake.retryCount > 0) ...[
                            const SizedBox(width: SpacingTokens.sm),
                            Text(
                              '重练 ${mistake.retryCount} 次',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // 常驻统计行：累计答错次数（与「重练 N 次」语义并存）
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    '累计答错 ${mistake.wrongCount} 次',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.1, end: 0, duration: 400.ms),

            const SizedBox(height: SpacingTokens.md),

            // 错因标签
            if (mistake.errorType != null) ...[
              ColoredCard(
                color: theme.colorScheme.error,
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    Text(
                      // 标签单一来源：math_engine kErrorCauseLabels；
                      // 未收录键回退显示英文原键（守卫内 errorType 非空）。
                      '错因：${errorCauseLabel(mistake.errorType)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 300.ms)
                  .slideX(begin: 0.1, end: 0, delay: 100.ms, duration: 300.ms),
              const SizedBox(height: SpacingTokens.md),
            ],

            // 解题步骤
            if (mistake.solutionStepsJson != null &&
                mistake.solutionStepsJson!.isNotEmpty)
              ColoredCard(
                color: theme.colorScheme.secondary,
                child: _buildSteps(context, mistake.solutionStepsJson!),
              ).animate().fadeIn(delay: 200.ms, duration: 300.ms).slideX(
                    begin: 0.1,
                    end: 0,
                    delay: 200.ms,
                    duration: 300.ms,
                  ),

            const SizedBox(height: SpacingTokens.lg),

            // 操作按钮
            _ActionButtons(
              mistake: mistake,
              problem: problem,
              onDeleted: () => context.pop(),
            ).animate().fadeIn(delay: 300.ms, duration: 300.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildSteps(BuildContext context, String stepsJson) {
    final theme = Theme.of(context);
    final lines = stepsJson.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '解题步骤',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        ...lines.map((line) {
          final parts = line.split('|||');
          final description = parts.isNotEmpty ? parts[0] : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Text(
                    description,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// 答案展示组件。
class _AnswerChip extends StatelessWidget {
  const _AnswerChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: SpacingTokens.xs),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 操作按钮区 — 一行展示所有按钮。
class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({
    required this.mistake,
    required this.problem,
    required this.onDeleted,
  });

  final MathMistake mistake;
  final MathProblem? problem;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _buildActionButton(
          icon: Icons.replay,
          label: '再练一次',
          onTap: () => _repractice(context, ref),
          color: theme.colorScheme.primary,
        ),
        // 「同类新题」按错因映射口算出题；应用题错题无对应映射，隐藏。
        if (mistake.problemType != 'llm_word_problem')
          _buildActionButton(
            icon: Icons.auto_awesome,
            label: '同类新题',
            onTap: () => _generateSimilar(context, ref),
            color: theme.colorScheme.primary,
          ),
        if (!mistake.isResolved)
          _buildActionButton(
            icon: Icons.check,
            label: '已掌握',
            tooltip: '跳过巩固抽查，直接标记为已掌握',
            onTap: () async {
              final repo = ref.read(mathMistakeRepoProvider);
              final ok = await _writeMistake(
                ScaffoldMessenger.of(context),
                '标记已掌握',
                () async {
                  await repo.resolve(mistake.id);
                },
              );
              if (!ok) return;
              ref.invalidate(mathMistakeRepoProvider);
            },
            color: theme.colorScheme.primary,
          ),
        _buildActionButton(
          icon: Icons.delete_outline,
          label: '删除',
          onTap: () async {
            // 在首个 await（对话框）之前捕获 messenger，供写入失败时提示。
            final messenger = ScaffoldMessenger.of(context);
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除错题'),
                content: const Text('确定要删除这道错题吗？'),
                actions: [
                  TextButton(
                    onPressed: () => ctx.pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => ctx.pop(true),
                    child: Text(
                      '删除',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            final repo = ref.read(mathMistakeRepoProvider);
            final ok = await _writeMistake(messenger, '删除错题', () async {
              await repo.delete(mistake.id);
            });
            if (!ok) return;
            ref.invalidate(mathMistakeRepoProvider);
            if (context.mounted) onDeleted();
          },
          color: theme.colorScheme.error,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    String? tooltip,
  }) {
    final button = TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.xs,
          vertical: SpacingTokens.xs,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    return Expanded(
      child:
          tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }

  /// 执行一次错题写入，失败时提示用户。
  ///
  /// `resolve` / `delete` / `recordRepracticeResult` 内部都是 `Hive.put/delete`，
  /// 磁盘满或 Box 损坏会抛 —— 且抛的是 `HiveError extends Error`，**不是**
  /// `Exception`，所以必须捕 `Object`。
  ///
  /// 原先三处写入全部裸 await：异常冒泡到框架，用户看到的是「点了没反应」
  /// ——「已掌握」按钮点了没变化、确认删除后错题还在原地。界面与真实状态
  /// 脱节且无任何解释，用户会反复点。这里统一补上日志 + 提示。
  ///
  /// 返回 true 表示写入成功，调用方据此决定是否 invalidate / 回调 onDeleted。
  ///
  /// 传入 [messenger] 而非 `BuildContext`：调用点普遍是「先 await 一个对话框、
  /// 再 await 写入」，`context` 会跨越 async gap，直接用它会被
  /// `use_build_context_synchronously` 判为不安全。调用方在首个 await 之前
  /// 捕获 `ScaffoldMessenger.of(context)`，语义等价且无 lint。
  Future<bool> _writeMistake(
    ScaffoldMessengerState messenger,
    String label,
    Future<void> Function() write,
  ) async {
    try {
      await write();
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '$label失败',
        tag: 'MathMistakeDetail',
        error: error,
        stackTrace: stackTrace,
      );
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$label失败，请重试')));
      return false;
    }
  }

  Future<void> _repractice(BuildContext context, WidgetRef ref) async {
    // 在首个 await（对话框）之前捕获 messenger。
    final messenger = ScaffoldMessenger.of(context);
    final result = await showMistakeRepractice(context, mistake);

    if (result == null) return;

    final repo = ref.read(mathMistakeRepoProvider);
    RepracticeOutcome? outcome;
    final ok = await _writeMistake(messenger, '提交巩固结果', () async {
      outcome = await repo.recordRepracticeResult(
        mistake.id,
        isCorrect: result,
      );
    });
    if (!ok) return;

    ref.invalidate(mathMistakeRepoProvider);

    // 巩固状态机反馈：进入巩固 / 通过一关 / 三关全过 / 打回未掌握。
    // 写入成功（ok == true）时 outcome 必已赋值；用局部变量承接以便提升类型。
    final settled = outcome;
    if (settled != null && context.mounted) {
      final updated = repo.getById(mistake.id) ?? mistake;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(repracticeOutcomeMessage(settled, updated)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _generateSimilar(BuildContext context, WidgetRef ref) {
    final skill = MathSkill.fromId(mistake.skillId);
    final semester = mistake.semester;
    if (skill == null || semester == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这道旧错题缺少知识点或学期记录，请使用原题回练')),
      );
      return;
    }
    ref.read(nextMathPracticeRequestProvider.notifier).setNext(
          MathPracticeRequest(
            grade: mistake.grade,
            semester: semester,
            count: 5,
            difficulty: DifficultyLevel.medium,
            skillId: skill.id,
            mode: problem?.mode == ProblemMode.vertical
                ? ProblemMode.vertical
                : null,
          ),
        );
    context.push(AppRoutes.mathPractice);
  }
}
