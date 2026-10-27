// lib/core/widgets/masonry_layout.dart
//
// 层级：core/widgets（共享布局组件）
// 职责：按列高最短优先的瀑布流布局（多列、自然高度、等高列宽）。
//
// 用法：
//   MasonryLayout(
//     columnCount: columns,
//     gap: SpacingTokens.sm,
//     children: [...],
//   )
//
// 从认一认字卡总览提取，供认一认与写一写字卡总览共用（纯布局，无业务语义）。

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 多列瀑布流：每个孩子按自身自然高度排入当前最矮的一列。
///
/// [columnCount] 会被夹到 1..8；[gap] 同时作为列间距与行间距。
/// 孩子宽度固定为列宽（`BoxConstraints.tightFor(width: columnWidth)`），
/// 因此孩子必须是「宽度可定、高度自适应」的组件（如卡片 Column）。
class MasonryLayout extends MultiChildRenderObjectWidget {
  const MasonryLayout({
    super.key,
    required this.columnCount,
    required this.gap,
    required super.children,
  });

  final int columnCount;
  final double gap;

  @override
  RenderMasonry createRenderObject(BuildContext context) =>
      RenderMasonry(columnCount: columnCount, gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderMasonry renderObject) {
    renderObject
      ..columnCount = columnCount
      ..gap = gap;
  }
}

class MasonryParentData extends ContainerBoxParentData<RenderBox> {}

class RenderMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MasonryParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MasonryParentData> {
  RenderMasonry({required int columnCount, required double gap})
      : _columnCount = columnCount,
        _gap = gap;

  int _columnCount;
  double _gap;

  int get columnCount => _columnCount;
  set columnCount(int value) {
    if (_columnCount == value) return;
    _columnCount = value;
    markNeedsLayout();
  }

  double get gap => _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MasonryParentData) {
      child.parentData = MasonryParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.minWidth;
    final columns = _columnCount.clamp(1, 8);
    final columnWidth =
        ((width - _gap * (columns - 1)) / columns).clamp(0.0, double.infinity);
    final columnHeights = List<double>.filled(columns, 0);
    var maxHeight = 0.0;

    var child = firstChild;
    while (child != null) {
      var shortestColumn = 0;
      for (var column = 1; column < columns; column++) {
        if (columnHeights[column] < columnHeights[shortestColumn]) {
          shortestColumn = column;
        }
      }
      child.layout(
        BoxConstraints.tightFor(width: columnWidth),
        parentUsesSize: true,
      );
      final y = columnHeights[shortestColumn];
      final parentData = child.parentData! as MasonryParentData;
      parentData.offset = Offset(
        shortestColumn * (columnWidth + _gap),
        y,
      );
      columnHeights[shortestColumn] = y + child.size.height + _gap;
      maxHeight = maxHeight < columnHeights[shortestColumn]
          ? columnHeights[shortestColumn]
          : maxHeight;
      child = childAfter(child);
    }

    size = constraints.constrain(
      Size(width, maxHeight == 0 ? 0 : maxHeight - _gap),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}