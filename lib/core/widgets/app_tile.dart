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
/// - 裸图标（无背景容器，颜色跟随 iconColor）
/// - 自定义前导内容（如题目缩略图）
/// - 标题 + 副标题文本列
/// - 尾部组件（默认为 chevron 箭头；可替换为 Switch 等）
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    this.icon,
    this.leading,
    this.leadingEdgeWidth,
    required this.iconColor,
    required this.title,
    this.titleSuffix,
    this.titleSuffixInline = false,
    required this.subtitle,
    this.onTap,
    this.allowTapWithTrailing = false,
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
    this.selected = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  })  : assert(trailing == null || trailingAction == null),
        assert(
          onTrailingTap == null || (trailing == null && trailingAction == null),
        ),
        assert(subtitleMaxLines == null || subtitleMaxLines > 0),
        assert(!selected || flat),
        assert(leadingEdgeWidth == null || leadingEdgeWidth > 0),
        assert(leadingEdgeWidth == null || (leading != null && !flat));

  /// 图标；未提供 [leading] 时展示，省略时不保留图标占位。
  final IconData? icon;

  /// 自定义前导内容，优先于 [icon]；未设置 [leadingEdgeWidth] 时应限制其宽度。
  final Widget? leading;

  /// 贴边前导内容的宽度；设置后铺满卡片起始侧的完整高度并沿卡片圆角裁切。
  /// 仅适用于提供 [leading] 的卡片列表行，文字和尾部操作保留默认内边距。
  final double? leadingEdgeWidth;

  /// 图标主色调，同时决定卡片背景色。
  final Color iconColor;

  /// 标题文本；为空时省略标题行，仅显示副标题内容。
  final String title;

  /// 紧跟标题的辅助信息；标题过长时省略，大字号空间不足时辅助信息另起一行。
  final String? titleSuffix;

  /// 将辅助信息作为标题内的文本，按基线对齐并随标题自然换行。
  final bool titleSuffixInline;

  /// 副标题文本。
  final String subtitle;

  /// 点击回调；自定义 [trailing] 默认独立处理交互，开启
  /// [allowTapWithTrailing] 后卡片内容也可响应此回调。
  final VoidCallback? onTap;

  /// 自定义尾部控件仍独立响应；为 true 时也允许点击卡片内容。
  final bool allowTapWithTrailing;

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

  /// 普通列表行（[flat]）的选中状态，提供主题高亮和辅助技术选中语义。
  final bool selected;

  /// 主行内前导内容、文本及尾部组件的垂直对齐方式。
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      color: selected ? theme.colorScheme.onPrimaryContainer : null,
    );
    final titleText = Text(
      title,
      maxLines: titleSuffix == null && trailingText == null ? null : 1,
      overflow: titleSuffix == null && trailingText == null
          ? null
          : TextOverflow.ellipsis,
      style: titleStyle,
    );
    final titleWidget = titleSuffix == null
        ? titleText
        : LayoutBuilder(
            builder: (context, constraints) {
              final suffixStyle = theme.textTheme.bodySmall?.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              );
              if (titleSuffixInline) {
                return Text.rich(
                  TextSpan(
                    text: title,
                    children: [
                      TextSpan(text: ' $titleSuffix', style: suffixStyle),
                    ],
                  ),
                  style: titleStyle,
                );
              }
              final suffix = Text(titleSuffix!, style: suffixStyle);
              final painter = TextPainter(
                text: TextSpan(text: titleSuffix, style: suffixStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final suffixWidth = painter.width;
              painter.dispose();
              if (suffixWidth + SpacingTokens.xs > constraints.maxWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleText, suffix],
                );
              }
              return Row(
                children: [
                  Flexible(child: titleText),
                  const SizedBox(width: SpacingTokens.xs),
                  suffix,
                ],
              );
            },
          );
    final trailingContent = trailing ??
        (onTrailingTap != null
            ? IconButton(
                tooltip: trailingTooltip,
                onPressed: onTrailingTap,
                color: selected ? theme.colorScheme.onPrimaryContainer : null,
                icon: Icon(trailingIcon),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    trailingIcon,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
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
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
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
          if (leadingEdgeWidth == null &&
              (leading != null || icon != null)) ...[
            leading ??
                Icon(
                  icon,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : iconColor,
                  size: 22,
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
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
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
      return Semantics(
        selected: selected ? true : null,
        child: Material(
          type: selected ? MaterialType.canvas : MaterialType.transparency,
          color: selected ? theme.colorScheme.primaryContainer : null,
          borderRadius: selected
              ? BorderRadius.circular(SpacingTokens.radiusSmall)
              : null,
          clipBehavior: selected ? Clip.antiAlias : Clip.none,
          child: InkWell(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
            onTap: trailing == null || allowTapWithTrailing ? onTap : null,
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
        ),
      );
    }
    const contentPadding = EdgeInsets.symmetric(
      horizontal: SpacingTokens.md,
      vertical: SpacingTokens.sm + 2,
    );
    final edgeWidth = leadingEdgeWidth;
    final cardContent = edgeWidth == null
        ? content
        : ClipRRect(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Padding(
                  padding: contentPadding.add(
                    EdgeInsetsDirectional.only(start: edgeWidth),
                  ),
                  child: content,
                ),
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: edgeWidth,
                  child: leading!,
                ),
              ],
            ),
          );
    return ColoredCard(
      color: iconColor,
      onTap: trailing == null || allowTapWithTrailing ? onTap : null,
      constraints: const BoxConstraints(
        minHeight: SpacingTokens.minTapTarget + SpacingTokens.md,
      ),
      padding: edgeWidth == null ? contentPadding : EdgeInsets.zero,
      child: cardContent,
    );
  }
}
