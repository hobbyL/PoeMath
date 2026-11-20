import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

/// 首页各区块共用标题样式，避免子模块自行加粗或更换字体。
class HomeSectionHeading extends StatelessWidget {
  const HomeSectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: theme.appearance.pine ? FontWeight.w500 : FontWeight.bold,
      ),
    );
  }
}

/// 目标、续练和今日清单共用分组；松墨的子项使用 AppTile.flat。
class HomeEntryGroup extends StatelessWidget {
  const HomeEntryGroup({
    super.key,
    required this.children,
    this.preferredTileWidth,
  });

  final List<Widget> children;
  final double? preferredTileWidth;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final grid = ResponsiveCardGrid(
      preferredTileWidth: preferredTileWidth,
      divided: theme.appearance.pine,
      children: children,
    );
    return theme.appearance.pine
        ? ColoredCard(
            color: theme.colorScheme.primary,
            // 行内留白由 AppTile 统一提供，外层再加会让首尾条目显得更高。
            padding: EdgeInsets.zero,
            child: grid,
          )
        : grid;
  }
}
