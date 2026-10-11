// lib/features/assistant/widgets/tool_message_card.dart
//
// 层级：features/assistant/widgets
// 职责：工具调用 / 工具结果的可折叠小卡（design §8）。基于 ColoredCard
//       （禁手写 BoxDecoration），tertiary 配色以区别于 user（primary）/
//       assistant（secondary）气泡；左对齐、默认折叠、点击展开，不喧宾夺主。
//       折叠时只露工具图标 + 标题；展开后显示结果 / 参数明细。
//
// 安全边界：仅渲染 content/工具名/参数等明文会话数据，绝不承载 API Key。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';

/// 工具名 → 家长 / 孩子可读的中文标签（未知名回退原样）。
String toolDisplayName(String name) => switch (name) {
      'generate_word_problems' => '出题',
      'open_practice' => '打开练习',
      'explain_mistake' => '讲解错题',
      _ => name,
    };

/// 可折叠工具消息小卡。
///
/// - [title]：折叠态标题（如「调用工具：出题」「工具结果：讲解错题」）。
/// - [detail]：展开态明细（参数 JSON / 工具结果文本）。
/// - [initiallyExpanded]：默认折叠（false），不喧宾夺主。
class ToolMessageCard extends StatefulWidget {
  const ToolMessageCard({
    super.key,
    required this.title,
    required this.detail,
    this.initiallyExpanded = false,
  });

  final String title;
  final String detail;
  final bool initiallyExpanded;

  @override
  State<ToolMessageCard> createState() => _ToolMessageCardState();
}

class _ToolMessageCardState extends State<ToolMessageCard> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    final color = theme.colorScheme.tertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ColoredCard(
            color: color,
            onTap: _toggle,
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.build_outlined, size: 18, color: color),
                    const SizedBox(width: SpacingTokens.sm),
                    Flexible(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.xs),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                if (_expanded && widget.detail.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    widget.detail.trim(),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
