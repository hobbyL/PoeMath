import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// AI 讲解/解析卡片标题右侧的「状态操作 tag」。
///
/// 行内徽标（非信息卡片/容器），与 AppTile 内图标容器同类，沿用
/// BoxDecoration + 设计令牌，不套 ColoredCard。相较原先的静态「AI 生成」
/// 角标，本控件承载状态相关的主操作（生成/重新生成/去设置），点击即触发
/// [onTap]；[onTap] 为空即禁用态（如加载中「生成中…」）。
///
/// 诗词 AI 讲解卡片与口算 AI 解析 sheet 共用，消灭两处同构徽标副本。
class AiActionTag extends StatelessWidget {
  const AiActionTag({
    super.key,
    required this.label,
    this.onTap,
    this.color,
    this.busy = false,
  });

  /// tag 文案，随讲解状态变化（生成讲解 / 生成中… / 重新生成 / 去设置）。
  final String label;

  /// 点击回调；为空表示禁用态（无点击态、无水波纹）。
  final VoidCallback? onTap;

  /// 主题色，默认 `colorScheme.tertiary`（与 AI 讲解卡片同色系）。
  final Color? color;

  /// 加载中：label 前置小转圈，通常与 `onTap == null` 同时出现。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagColor = color ?? theme.colorScheme.tertiary;

    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tagColor,
              ),
            ),
            const SizedBox(width: SpacingTokens.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: tagColor),
          ),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
        child: content,
      ),
    );
  }
}
