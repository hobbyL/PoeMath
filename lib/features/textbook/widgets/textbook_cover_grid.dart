import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';

/// 管理与下载页面共用的封面栅格：从左到右，排满后向下换行。
class TextbookCoverGrid extends StatelessWidget {
  const TextbookCoverGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.naturalRowHeight = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool naturalRowHeight;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          final gridWidth = constraints.crossAxisExtent - SpacingTokens.md * 2;
          const targetCoverWidth = 180.0;
          final columns = (gridWidth / targetCoverWidth).floor().clamp(2, 6);
          if (naturalRowHeight) {
            final rows = (itemCount / columns).ceil();
            return SliverPadding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              sliver: SliverList.builder(
                itemCount: rows,
                itemBuilder: (context, row) => Padding(
                  padding: EdgeInsets.only(
                    bottom: row == rows - 1 ? 0 : SpacingTokens.md,
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0)
                            const SizedBox(width: SpacingTokens.md),
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
              ),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            sliver: SliverGrid.builder(
              itemCount: itemCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: SpacingTokens.md,
                crossAxisSpacing: SpacingTokens.md,
                childAspectRatio: 3 / 4,
              ),
              itemBuilder: itemBuilder,
            ),
          );
        },
      );
}
