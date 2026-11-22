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
        fontWeight: theme.appearance.ink ? FontWeight.w500 : FontWeight.w600,
      ),
    );
  }
}

/// 水墨主题使用整张纸面分组；童趣主题保留各自的卡片间距和轮廓。
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
    final entries = theme.appearance.ink
        ? [
            for (final child in children)
              if (child is AppTile)
                child.copyWith(flatTrailingIconInset: true)
              else
                child,
          ]
        : children;
    final grid = ResponsiveCardGrid(
      preferredTileWidth: preferredTileWidth,
      divided: theme.appearance.ink,
      children: entries,
    );
    return theme.appearance.ink
        ? ColoredCard(
            color: theme.colorScheme.primary,
            // 行内留白由 AppTile 统一提供，外层再加会让首尾条目显得更高。
            padding: EdgeInsets.zero,
            child: grid,
          )
        : grid;
  }
}
