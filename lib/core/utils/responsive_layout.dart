// lib/core/utils/responsive_layout.dart
//
// 层级：core/utils
// 职责：跨页面共用的响应式布局换算（栅格列数、内容最大宽度）。

/// 响应式栅格换算。
///
/// 原先 7 个页面各自私有一份完全相同的 `_responsiveColumns`
/// （收起/错题/挑战历史/练习详情/诗词/知识库/收藏），断点漂移一处就会
/// 出现「同一块屏不同页面列数不同」的观感割裂。统一收敛到此处，页面只
/// 负责把 `constraints.maxWidth` 传进来。
class ResponsiveLayout {
  const ResponsiveLayout._();

  /// 宽屏（平板横屏 / 桌面）断点：三列。
  static const double wideBreakpoint = 900;

  /// 窄屏（平板竖屏）断点：两列。
  static const double mediumBreakpoint = 600;

  /// 按可用宽度返回栅格列数：≥900 三列，≥600 两列，否则一列。
  ///
  /// 断点与 [wideBreakpoint] / [mediumBreakpoint] 保持一致，页面若需
  /// 自定义阈值请直接比较这两个常量，不要复制魔法数字。
  static int columns(double width) {
    if (width >= wideBreakpoint) return 3;
    if (width >= mediumBreakpoint) return 2;
    return 1;
  }
}
