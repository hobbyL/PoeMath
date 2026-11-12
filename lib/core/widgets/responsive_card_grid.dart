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

/// Lazy rows with natural heights, for long card collections in a sliver view.
class SliverCardGrid extends StatelessWidget {
  const SliverCardGrid({
    super.key,
    required this.columnCount,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int columnCount;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final columns = (columnCount / scale).floor().clamp(1, columnCount);
    return SliverList.builder(
      itemCount: (itemCount / columns).ceil(),
      itemBuilder: (context, row) => Padding(
        padding: EdgeInsets.only(top: row == 0 ? 0 : SpacingTokens.sm),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: row * columns + column < itemCount
                      ? itemBuilder(context, row * columns + column)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
