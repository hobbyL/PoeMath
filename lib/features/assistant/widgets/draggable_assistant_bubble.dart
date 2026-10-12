// lib/features/assistant/widgets/draggable_assistant_bubble.dart
//
// 层级：features/assistant/widgets
// 职责：挂于 MainShell 的全局可拖拽悬浮气泡 —— AI 助手的跨页入口。
//       拖拽改位置、松手贴最近水平边吸附；点击（小位移）跳转助手页。
//       停留位置落 settings box（assistant_bubble_dx/dy），首帧经
//       LayoutBuilder 边界校验后恢复（越界回落），跨启动保持。
// 依赖：Flutter 手势 / Riverpod（appRouterProvider context-free 导航）。
//
// 例外说明：本组件是「不使用浮动按钮」与「卡片必须用 ColoredCard」两条
//   项目约定的既定例外（见 .trellis/spec/frontend/component-guidelines.md
//   「全局悬浮气泡例外」小节）。圆形面用 Material(shape: CircleBorder) +
//   InkWell，非手写 BoxDecoration，颜色走 theme.colorScheme、尺寸用常量。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/providers/repository_providers.dart';

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

  /// 是否已把持久化位置恢复进 [_position]（只恢复一次，避免每帧重读）。
  bool _restoredFromStorage = false;

  /// 当前帧解析出的定位边界，供手势回调复用（避免回调里重算约束）。
  _Bounds? _bounds;

  /// AnimatedPositioned 时长：拖拽跟手为 0，松手贴边才启用过渡。
  Duration _moveDuration = Duration.zero;

  /// 首帧（LayoutBuilder 解析出边界后）恢复持久化位置：越界（屏幕
  /// 尺寸变化 / 换设备）经 [_clampToBounds] 回落到边界内；无存档或
  /// 严重越界保持 null → 默认角。
  void _restoreFromStorage(_Bounds bounds) {
    if (_restoredFromStorage) return;
    _restoredFromStorage = true;
    final repo = ref.read(settingsRepositoryProvider);
    final dx = repo.assistantBubbleDx;
    final dy = repo.assistantBubbleDy;
    if (dx == null || dy == null) return;
    final saved = Offset(dx, dy);
    final withinBounds = saved.dx >= bounds.minX &&
        saved.dx <= bounds.maxX &&
        saved.dy >= bounds.minY &&
        saved.dy <= bounds.maxY;
    if (!withinBounds) return; // 严重越界：弃用存档，用默认角
    _position = _clampToBounds(saved, bounds);
  }

  /// 松手贴边后的最终位置持久化（拖拽过程不写，避免高频 IO）。
  /// 失败仅记日志，不影响交互。
  Future<void> _persistPosition(Offset pos) async {
    try {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.setAssistantBubbleDx(pos.dx);
      await repo.setAssistantBubbleDy(pos.dy);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '悬浮球位置持久化失败',
        tag: 'Assistant',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

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
    final snapped = Offset(snappedX, current.dy);
    setState(() {
      _moveDuration = _snapDuration;
      _position = snapped;
    });
    // 贴边吸附的最终位置落盘，下次启动恢复。
    unawaited(_persistPosition(snapped));
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
        // 首帧恢复持久化位置（需要边界才能判断越界回落）。
        _restoreFromStorage(bounds);

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
