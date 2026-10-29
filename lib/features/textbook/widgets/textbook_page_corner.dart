import 'dart:math' as math;
import 'dart:ui';

import 'package:poemath/core/theme/spacing_tokens.dart';

enum TextbookPageCorner { previous, next }

/// 只识别书页下方两角，点击范围以屏幕逻辑像素计，不随 PDF 放大。
TextbookPageCorner? textbookPageCornerAt(Offset point, Rect pageBounds) {
  if (!pageBounds.contains(point)) return null;
  final extent = math.min(
    SpacingTokens.minTapTarget * 2,
    math.min(pageBounds.width, pageBounds.height) / 2,
  );
  if (point.dy < pageBounds.bottom - extent) return null;
  if (point.dx < pageBounds.left + extent) {
    return TextbookPageCorner.previous;
  }
  if (point.dx >= pageBounds.right - extent) return TextbookPageCorner.next;
  return null;
}
