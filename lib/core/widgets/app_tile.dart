// lib/core/widgets/app_tile.dart
//
// 层级：core/widgets
// 职责：通用设置行/列表行组件 — 图标 + 标题 + 副标题 + 尾部操作。
//
// 用法：
//   AppTile(
//     icon: Icons.palette_outlined,
//     iconColor: theme.colorScheme.primary,
//     title: '主题设置',
//     subtitle: '诗词',
//     onTap: () => ...,
//   )
//
// 所有设置项、功能列表项等都应使用此组件。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';

/// 通用列表行组件。
///
/// 视觉规则继承 [ColoredCard]（半透明彩色背景 + 圆角），额外提供：
/// - 可选的 40×40 圆角图标容器（12% 透明度）
/// - 标题 + 副标题文本列
/// - 尾部组件（默认为 chevron 箭头；可替换为 Switch 等）
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    this.icon,
    required this.iconColor,
    required this.title,
    this.titleSuffix,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.trailingText,
    this.trailingAction,
    this.trailingInTitle = false,
    this.trailingIcon = Icons.chevron_right,
    this.onTrailingTap,
    this.trailingTooltip,
    this.subtitleMaxLines,
    this.flat = false,
    this.flatTrailingEdgeAligned = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  })  : assert(trailing == null || trailingAction == null),
        assert(
          onTrailingTap == null || (trailing == null && trailingAction == null),
        ),
        assert(subtitleMaxLines == null || subtitleMaxLines > 0);

  /// 图标；省略时不展示图标，也不保留图标占位。
  final IconData? icon;

  /// 图标主色调，同时决定卡片背景色。
  final Color iconColor;

  /// 标题文本；为空时省略标题行，仅显示副标题内容。
  final String title;

  /// 紧跟标题的单行辅助信息；标题过长时省略，保留辅助信息。
  final String? titleSuffix;

  /// 副标题文本。
  final String subtitle;

  /// 点击回调；若 [trailing] 不为空则忽略（由 trailing 自行处理交互）。
  final VoidCallback? onTap;

  /// 尾部组件。为 null 时显示 chevron 箭头。
  final Widget? trailing;

  /// 箭头前靠右显示的单行状态文字；保留整行点击，长文字省略。
  final String? trailingText;

  /// 默认箭头下方的独立操作，与主行并排；不能与 [trailing] 同时使用。
  final Widget? trailingAction;

  /// 将尾部组件放在标题行右侧，副标题可使用整行宽度。
  final bool trailingInTitle;

  /// 默认尾部箭头，可用于同一行的展开/收起状态。
  final IconData trailingIcon;

  /// 行末按钮可独立处理展开，主行仍可使用 [onTap] 导航。
  final VoidCallback? onTrailingTap;
  final String? trailingTooltip;

  /// 副标题最大行数；设置后超出部分以省略号显示，默认不限制。
  final int? subtitleMaxLines;

  /// 普通列表行，无独立卡片背景或圆角，适用于抽屉目录。
  final bool flat;

  /// 普通列表行中将尾部图形贴到内容区右边界；整行仍保留 44dp 点击高度。
  final bool flatTrailingEdgeAligned;

  /// 主行内图标、文本及尾部组件的垂直对齐方式。
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = Text(
      title,
      maxLines: titleSuffix == null && trailingText == null ? null : 1,
      overflow: titleSuffix == null && trailingText == null
          ? null
          : TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    final titleWidget = titleSuffix == null
        ? titleText
        : Row(
            children: [
              Flexible(child: titleText),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                titleSuffix!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
    final trailingContent = trailing ??
        (onTrailingTap != null
            ? IconButton(
                tooltip: trailingTooltip,
                onPressed: onTrailingTap,
                icon: Icon(trailingIcon),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    trailingIcon,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  if (trailingAction != null) trailingAction!,
                ],
              ));
    final trailingWidget = flat
        ? flatTrailingEdgeAligned
            ? SizedBox(
                height: SpacingTokens.minTapTarget,
                child: Align(
                  widthFactor: 1,
                  alignment: AlignmentDirectional.centerEnd,
                  child: trailingContent,
                ),
              )
            : SizedBox.square(
                dimension: SpacingTokens.minTapTarget,
                child: Align(child: trailingContent),
              )
        : trailingContent;
    final hasTitleRow =
        title.isNotEmpty || titleSuffix != null || trailingInTitle;
    Widget buildContent(double maxTrailingWidth) {
      final trailingWithText = trailingText == null
          ? trailingWidget
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTrailingWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const SizedBox(width: SpacingTokens.sm),
                  Flexible(
                    child: Text(
                      trailingText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (flat && flatTrailingEdgeAligned)
                    const SizedBox(width: SpacingTokens.xs),
                  trailingWidget,
                ],
              ),
            );

      return Row(
        crossAxisAlignment: crossAxisAlignment,
        children: <Widget>[
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: SpacingTokens.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (hasTitleRow && trailingInTitle)
                  Row(
                    children: [
                      Expanded(child: titleWidget),
                      const SizedBox(width: SpacingTokens.sm),
                      trailingWithText,
                    ],
                  )
                else if (hasTitleRow)
                  titleWidget,
                if (!flat || subtitle.isNotEmpty) ...[
                  if (hasTitleRow) const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: subtitleMaxLines,
                    overflow:
                        subtitleMaxLines == null ? null : TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!trailingInTitle) trailingWithText,
        ],
      );
    }

    final content = trailingText == null
        ? buildContent(double.infinity)
        : LayoutBuilder(
            builder: (context, constraints) =>
                buildContent(constraints.maxWidth / 2),
          );
    if (flat) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: trailing == null ? onTap : null,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: SpacingTokens.minTapTarget),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                SpacingTokens.sm,
                SpacingTokens.xs,
                flatTrailingEdgeAligned ? 0 : SpacingTokens.sm,
                SpacingTokens.xs,
              ),
              child: content,
            ),
          ),
        ),
      );
    }
    return ColoredCard(
      color: iconColor,
      onTap: trailing == null ? onTap : null,
      constraints: const BoxConstraints(
        minHeight: SpacingTokens.minTapTarget + SpacingTokens.md,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm + 2,
      ),
      child: content,
    );
  }
}
