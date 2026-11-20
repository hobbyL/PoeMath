import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';

/// 统一的空内容与无结果提示，可用于页面、Sliver 或列表中的空区域。
///
/// 有界高度时居中展示，空间不足时可滚动；放在外层滚动容器中时按内容
/// 高度布局。操作由页面提供，保持原有导航与权限检查。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actions = const [],
    this.padding = const EdgeInsets.all(SpacingTokens.xl),
  });

  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glyph = ExcludeSemantics(
      child: Icon(
        icon,
        size: SpacingTokens.xxl,
        color: theme.appearance.playful
            ? theme.colorScheme.primary
            : theme.colorScheme.primary.withValues(alpha: 0.5),
      ),
    );
    final alignment = theme.appearance.space
        ? TextAlign.start
        : TextAlign.center;
    final message = <Widget>[
      Semantics(
        header: true,
        child: Text(
          title,
          textAlign: alignment,
          style: theme.textTheme.titleMedium,
        ),
      ),
      if (description != null) ...[
        const SizedBox(height: SpacingTokens.xs),
        Text(
          description!,
          textAlign: alignment,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (actions.isNotEmpty) ...[
        const SizedBox(height: SpacingTokens.lg),
        Wrap(
          alignment: alignment == TextAlign.start
              ? WrapAlignment.start
              : WrapAlignment.center,
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.sm,
          children: actions,
        ),
      ],
    ];
    return Center(
      child: SingleChildScrollView(
        primary: false,
        padding: padding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ResponsiveLayout.mediumBreakpoint,
          ),
          child: Column(
            crossAxisAlignment: theme.appearance.space
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              glyph,
              const SizedBox(height: SpacingTokens.md),
              ...message,
            ],
          ),
        ),
      ),
    );
  }
}
