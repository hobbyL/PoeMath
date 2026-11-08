import 'package:flutter/widgets.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/masonry_layout.dart';

/// 按内容区宽度排列自然高度的卡片；卡片不足时铺满可用列。
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => MasonryLayout(
        columnCount: ResponsiveLayout.columns(constraints.maxWidth)
            .clamp(1, children.length),
        gap: SpacingTokens.sm,
        children: children,
      ),
    );
  }
}
