import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/domain/math_entry_kind.dart';

/// 引导与设置共用的学习背景表单；修改仅通过回调交给调用方保存。
///
/// [kinds] 为 null 时不渲染「练习类型」区块 —— 引导页只问年级学期，
/// 不该在这里塞入口配置（首次使用还没有"要练哪几类"的语境）。
class LearningBackgroundFields extends StatelessWidget {
  const LearningBackgroundFields({
    super.key,
    required this.grade,
    required this.semester,
    required this.onChanged,
    this.kinds,
    this.onKindsChanged,
  });

  final int grade;
  final String semester;
  final void Function(int grade, String semester) onChanged;

  /// 当前启用的口算练习类型；null = 不显示该区块。
  final Set<MathEntryKind>? kinds;

  /// 练习类型变更回调；[kinds] 非 null 时必须提供。
  final void Function(Set<MathEntryKind> kinds)? onKindsChanged;

  /// 练习类型的中文名（与卡片标题一致，便于用户对应）。
  static String _kindLabel(MathEntryKind kind) => switch (kind) {
        MathEntryKind.arithmetic => '口算',
        MathEntryKind.vertical => '竖式',
        MathEntryKind.wordProblem => '应用题',
        MathEntryKind.challenge => '挑战',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentKinds = kinds;
    final notifyKinds = onKindsChanged;
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('正在学习哪一册？', style: theme.textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.md),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.xs,
            children: [
              for (var value = 1; value <= 6; value++)
                ChoiceChip(
                  label: Text('$value 年级'),
                  selected: grade == value,
                  onSelected: (_) => onChanged(value, semester),
                ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Wrap(
            spacing: SpacingTokens.sm,
            children: [
              for (final value in const ['上', '下'])
                ChoiceChip(
                  label: Text('$value学期'),
                  selected: semester == value,
                  onSelected: (_) => onChanged(grade, value),
                ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            '用于诗词、口算和每日推荐。临时浏览其他年级不会修改这里的选择，之后也可在设置中调整。',
            style: theme.textTheme.bodySmall,
          ),
          if (currentKinds != null && notifyKinds != null) ...[
            const SizedBox(height: SpacingTokens.lg),
            Text('口算页显示哪些练习？', style: theme.textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              '选择后，口算页只显示勾选的练习类型。至少要保留一类。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: SpacingTokens.sm),
            Wrap(
              spacing: SpacingTokens.sm,
              runSpacing: SpacingTokens.xs,
              children: [
                for (final kind in MathEntryKind.values)
                  FilterChip(
                    label: Text(_kindLabel(kind)),
                    selected: currentKinds.contains(kind),
                    // 取消最后一项时不响应：空集合会让口算页无入口，
                    // 在 UI 层就挡住，而不是等保存时再报错。
                    onSelected: (selected) {
                      if (!selected && currentKinds.length <= 1) return;
                      final next = {...currentKinds};
                      if (selected) {
                        next.add(kind);
                      } else {
                        next.remove(kind);
                      }
                      notifyKinds(next);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
