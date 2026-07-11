// lib/core/theme/spacing_tokens.dart
//
// 层级：core/theme（设计令牌 - 间距/圆角/阴影）
// 职责：8pt 栅格间距、圆角、命中区、阴影常量。
// 规则：所有 padding/margin/borderRadius 都优先取这里的常量。

import 'package:flutter/material.dart';

class SpacingTokens {
  const SpacingTokens._();

  // ============ 8pt 栅格 ============
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // ============ 圆角 ============
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 24.0;
  static const double radiusPill = 999.0;

  // ============ 无障碍：命中区域下限 ============
  static const double minTapTarget = 44.0;

  // ============ 阴影 ============
  static const List<BoxShadow> softShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> notchShadow = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
}
