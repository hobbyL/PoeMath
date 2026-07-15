// lib/features/shell/widgets/notched_bottom_bar.dart
//
// 层级：features/shell/widgets
// 职责：自绘的 5-Tab 底部导航栏（左 2 + 中央凸起 + 右 2）。
//       通过 CustomPainter 挖出凹槽，中央按钮悬浮在凹槽上方形成"托举"。
// 依赖：DesignTokens.spacing。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';

/// 单个 tab 项配置。
class NavItem {
  const NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// 带中央凸起的底部导航栏。
///
/// - [items] 长度必须为 4（左 2 + 右 2），中央凸起独立以 [onCenterTap] 处理。
/// - [currentIndex] 使用 0..3 表示 4 个非中央 tab；中央按钮不参与 index。
class NotchedBottomBar extends StatelessWidget {
  const NotchedBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.onCenterTap,
    this.centerIcon = Icons.auto_stories,
  }) : assert(items.length == 4, 'NotchedBottomBar 需要 4 个 NavItem'),
       assert(currentIndex >= 0 && currentIndex < 4, 'currentIndex 越界');

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavItem> items;
  final VoidCallback onCenterTap;
  final IconData centerIcon;

  static const double _barHeight = 68.0;
  static const double _notchRadius = 30.0;
  static const double _fabDiameter = 56.0;
  /// FAB 伸出底栏顶部的高度（仅露出上半弧的一部分）。
  static const double _fabTopReserve = 20.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final primary = theme.colorScheme.primary;
    final inactive = theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      height: _barHeight + _fabTopReserve,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          // 1) 底部条：CustomPaint 挖凹槽 + Row 排布 4 个 tab
          Positioned(
            left: 0,
            right: 0,
            top: _fabTopReserve,
            bottom: 0,
            child: CustomPaint(
              painter: _NotchedBarPainter(
                color: surface,
                notchRadius: _notchRadius,
                shadowColor: theme.shadowColor,
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: _barHeight,
                  child: Row(
                    children: <Widget>[
                      _buildTab(context, 0, items[0], primary, inactive),
                      _buildTab(context, 1, items[1], primary, inactive),
                      const SizedBox(width: 72), // 中央留白给 FAB
                      _buildTab(context, 2, items[2], primary, inactive),
                      _buildTab(context, 3, items[3], primary, inactive),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 2) 中央凸起按钮 — 大部分嵌入底栏凹槽内，仅上弧露出
          Positioned(
            bottom: _barHeight - _fabDiameter + _fabTopReserve,
            left: 0,
            right: 0,
            child: Center(
              child: _CenterFab(
                icon: centerIcon,
                backgroundColor: primary,
                onTap: onCenterTap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    int index,
    NavItem item,
    Color activeColor,
    Color inactiveColor,
  ) {
    final selected = index == currentIndex;
    final color = selected ? activeColor : inactiveColor;
    return Expanded(
      child: InkResponse(
        onTap: () => onTap(index),
        radius: 32,
        child: SizedBox(
          height: SpacingTokens.minTapTarget,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(item.icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部条自绘：顶部中央挖一个半圆凹槽。
class _NotchedBarPainter extends CustomPainter {
  _NotchedBarPainter({
    required this.color,
    required this.notchRadius,
    required this.shadowColor,
  });

  final Color color;
  final double notchRadius;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final cx = size.width / 2;

    // 左侧顶边
    path.moveTo(0, 0);
    path.lineTo(cx - notchRadius - 8, 0);

    // 左侧过渡曲线到凹槽起点
    path.quadraticBezierTo(cx - notchRadius, 0, cx - notchRadius, 4);

    // 凹槽（半圆向下）
    path.arcToPoint(
      Offset(cx + notchRadius, 4),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // 右侧过渡曲线
    path.quadraticBezierTo(cx + notchRadius, 0, cx + notchRadius + 8, 0);

    // 右侧顶边
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    // 阴影：上探效果
    canvas.drawShadow(path, shadowColor, 8, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _NotchedBarPainter old) =>
      old.color != color ||
      old.notchRadius != notchRadius ||
      old.shadowColor != shadowColor;
}

/// 中央凸起圆形按钮。
class _CenterFab extends StatelessWidget {
  const _CenterFab({
    required this.icon,
    required this.backgroundColor,
    required this.onTap,
  });

  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shape: const CircleBorder(),
      color: backgroundColor,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: NotchedBottomBar._fabDiameter,
          height: NotchedBottomBar._fabDiameter,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
