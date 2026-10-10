// lib/features/assistant/widgets/draggable_assistant_bubble.dart
//
// 层级：features/assistant/widgets
// 职责：挂于 MainShell 的全局可拖拽悬浮气泡 —— AI 助手的跨页入口。
//       拖拽改位置、松手贴最近水平边吸附；点击（小位移）跳转助手页。
// 依赖：Flutter 手势 / Riverpod（appRouterProvider context-free 导航）。
//
// 例外说明：本组件是「不使用浮动按钮」与「卡片必须用 ColoredCard」两条
//   项目约定的既定例外（见 .trellis/spec/frontend/component-guidelines.md
//   「全局悬浮气泡例外」小节）。圆形面用 Material(shape: CircleBorder) +
//   InkWell，非手写 BoxDecoration，颜色走 theme.colorScheme、尺寸用常量。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 气泡定位边界（body 坐标系，已扣除安全区与边距）。
typedef _Bounds = ({double minX, double maxX, double minY, double maxY});

/// 全局可拖拽的 AI 助手悬浮气泡。
///
/// 作为 [Stack] 的直接子级挂在 `MainShell` 的 body 上，仅在 4 个 tab
/// 页随 Shell 可见；经 `context.push` 打开的全屏页在 Shell 之上另起路由栈，
/// 天然不叠加本气泡。
class DraggableAssistantBubble extends ConsumerStatefulWidget {
  const DraggableAssistantBubble({super.key});

  @override
  ConsumerState<DraggableAssistantBubble> createState() =>
      _DraggableAssistantBubbleState();
}

class _DraggableAssistantBubbleState
    extends ConsumerState<DraggableAssistantBubble> {
  /// 气泡直径（FAB 量级）。无对应间距令牌，取具名常量避免散落魔法数字。
  static const double _diameter = 56.0;

  /// 圆形面阴影高度。
  static const double _elevation = 6.0;

  /// 距 body 四边的安全边距。
  static const double _margin = SpacingTokens.md;

  /// 松手贴边吸附过渡时长。
  static const Duration _snapDuration = Duration(milliseconds: 220);

  /// 气泡左上角位置（body 坐标系）；null 表示尚未交互，用默认角。
  Offset? _position;

  /// 当前帧解析出的定位边界，供手势回调复用（避免回调里重算约束）。
  _Bounds? _bounds;

  /// AnimatedPositioned 时长：拖拽跟手为 0，松手贴边才启用过渡。
  Duration _moveDuration = Duration.zero;

  // TODO(assistant-bubble): 跨 App 重启的位置持久化（落 settings box 的
  //   assistant_bubble_dx/dy，initState 读取）为可选增强，本轮不做。

  Offset _clampToBounds(Offset pos, _Bounds b) {
    return Offset(
      pos.dx.clamp(b.minX, b.maxX),
      pos.dy.clamp(b.minY, b.maxY),
    );
  }

  void _onPanStart(DragStartDetails _) {
    final b = _bounds;
    if (b == null) return;
    // 从当前解析位置起拖（首次交互时锚定到默认角）。
    _position = _clampToBounds(_position ?? Offset(b.maxX, b.maxY), b);
    _moveDuration = Duration.zero;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final b = _bounds;
    final current = _position;
    if (b == null || current == null) return;
    setState(() {
      _moveDuration = Duration.zero;
      _position = _clampToBounds(current + details.delta, b);
    });
  }

  void _onPanEnd(DragEndDetails _) {
    final b = _bounds;
    final current = _position;
    if (b == null || current == null) return;
    // 比较气泡中心 x 与屏幕中线，贴最近水平边。
    final centerX = current.dx + _diameter / 2;
    final midline = (b.minX + b.maxX + _diameter) / 2;
    final snappedX = centerX < midline ? b.minX : b.maxX;
    setState(() {
      _moveDuration = _snapDuration;
      _position = Offset(snappedX, current.dy);
    });
  }

  void _openAssistant() {
    ref.read(appRouterProvider).push(AppRoutes.assistant);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        // 顶部避让状态栏，四周留边距；窄屏下保证 min ≤ max。
        final minX = _margin;
        final maxX = (maxW - _diameter - _margin).clamp(minX, double.infinity);
        final minY = topInset + _margin;
        final maxY = (maxH - _diameter - _margin).clamp(minY, double.infinity);
        final bounds = (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
        _bounds = bounds;

        // 默认右下角；已交互则用当前位置（随约束变化重新 clamp）。
        final pos = _clampToBounds(
          _position ?? Offset(maxX, maxY),
          bounds,
        );

        return SizedBox(
          width: maxW,
          height: maxH,
          child: Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: _moveDuration,
                curve: Curves.easeOut,
                left: pos.dx,
                top: pos.dy,
                width: _diameter,
                height: _diameter,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: _buildBubble(theme),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBubble(ThemeData theme) {
    return Material(
      color: theme.colorScheme.primary,
      shape: const CircleBorder(),
      elevation: _elevation,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openAssistant,
        child: Icon(
          Icons.smart_toy_outlined,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
