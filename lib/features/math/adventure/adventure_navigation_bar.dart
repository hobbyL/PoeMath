import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';

/// Uses the same measured height for every region so scrolling never resizes
/// the viewport. Large text gets the full width below the navigation controls.
class AdventureNavigationBar extends StatelessWidget
    implements PreferredSizeWidget {
  AdventureNavigationBar({
    super.key,
    required BuildContext context,
    required this.region,
    required this.onBack,
    required this.onAlbum,
    required this.onLocate,
  }) {
    final theme = Theme.of(context);
    _titleStyle = theme.textTheme.titleLarge!.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.bold,
    );
    _subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final width =
        MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;
    // Reserve two actions even at the end of a completed route.
    final inlineWidth =
        width - kToolbarHeight - SpacingTokens.xxl * 2 - SpacingTokens.md * 2;
    _stacked = inlineWidth < scaler.scale(SpacingTokens.xxl * 4);
    final textWidth = math.max(
      1.0,
      _stacked ? width - SpacingTokens.md * 2 : inlineWidth,
    );
    double height(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: textWidth);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    _textHeight =
        MathAdventureRegion.values
            .map(
              (r) =>
                  height(r.title, _titleStyle) +
                  SpacingTokens.xs +
                  height(r.subtitle, _subtitleStyle),
            )
            .reduce(math.max) +
        SpacingTokens.sm * 2;
  }

  final MathAdventureRegion? region;
  final VoidCallback onBack, onAlbum;
  final VoidCallback? onLocate;
  late final TextStyle _titleStyle, _subtitleStyle;
  late final bool _stacked;
  late final double _textHeight;

  @override
  Size get preferredSize => Size.fromHeight(
    _stacked
        ? kToolbarHeight + _textHeight
        : math.max(kToolbarHeight, _textHeight),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            region?.title ?? '数学探险',
            textAlign: TextAlign.center,
            style: _titleStyle,
          ),
          if (region != null) ...[
            const SizedBox(height: SpacingTokens.xs),
            Text(
              region!.subtitle,
              textAlign: TextAlign.center,
              style: _subtitleStyle,
            ),
          ],
        ],
      ),
    );
    return AppBar(
      backgroundColor: scheme.surface.withValues(alpha: 0),
      surfaceTintColor: scheme.surface.withValues(alpha: 0),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      forceMaterialTransparency: true,
      systemOverlayStyle:
          (scheme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: scheme.surface.withValues(alpha: 0)),
      centerTitle: true,
      titleSpacing: SpacingTokens.md,
      leading: BackButton(onPressed: onBack),
      toolbarHeight: _stacked ? kToolbarHeight : preferredSize.height,
      title: _stacked ? null : title,
      bottom: _stacked
          ? PreferredSize(
              preferredSize: Size.fromHeight(_textHeight),
              child: SizedBox(
                height: _textHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                  ),
                  child: Center(child: title),
                ),
              ),
            )
          : null,
      actions: [
        if (onLocate != null)
          IconButton(
            tooltip: '找到当前关卡',
            onPressed: onLocate,
            icon: const Icon(Icons.near_me_outlined),
          ),
        IconButton(
          tooltip: '打开纪念册',
          onPressed: onAlbum,
          icon: const Icon(Icons.collections_bookmark_outlined),
        ),
      ],
    );
  }
}
