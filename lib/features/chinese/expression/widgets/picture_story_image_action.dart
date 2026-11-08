import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_contrast.dart';

/// 题图上的透明操作按钮：卡片与详情共用局部取色、描边和点击尺寸。
/// 静态图片由 surfaceKey 测量；视差场景额外传入滚动与图片布局参数。
class PictureStoryImageAction extends StatefulWidget {
  const PictureStoryImageAction({
    super.key,
    required this.surfaceKey,
    this.scroll,
    required this.pixels,
    this.viewport,
    this.imageSize,
    this.parallaxFactor = 0,
    required this.child,
  });

  final GlobalKey surfaceKey;
  final ScrollController? scroll;
  final PictureStorySceneContrast? pixels;
  final Size? viewport;
  final Size? imageSize;
  final double parallaxFactor;
  final Widget child;

  @override
  State<PictureStoryImageAction> createState() =>
      _PictureStoryImageActionState();
}

class _PictureStoryImageActionState extends State<PictureStoryImageAction> {
  Rect? _iconRect;
  Size? _surfaceSize;
  bool? _lightForeground;
  bool _measurementPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureAfterLayout();
  }

  @override
  void didUpdateWidget(PictureStoryImageAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pixels != widget.pixels) _lightForeground = null;
    _measureAfterLayout();
  }

  void _measureAfterLayout() {
    if (_measurementPending) return;
    _measurementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementPending = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      final scene = widget.surfaceKey.currentContext?.findRenderObject();
      if (box is! RenderBox ||
          scene is! RenderBox ||
          !box.hasSize ||
          !scene.hasSize) {
        return;
      }
      final center = scene.globalToLocal(
        box.localToGlobal(box.size.center(Offset.zero)),
      );
      final size = IconTheme.of(context).size ?? SpacingTokens.lg;
      final rect = Rect.fromCenter(center: center, width: size, height: size);
      if (rect != _iconRect || scene.size != _surfaceSize) {
        setState(() {
          _iconRect = rect;
          _surfaceSize = scene.size;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.scroll ?? const AlwaysStoppedAnimation<double>(0),
    child: widget.child,
    builder: (context, child) {
      final theme = Theme.of(context);
      final scroll = widget.scroll;
      final offset = scroll != null && scroll.hasClients ? scroll.offset : 0.0;
      final viewport = widget.viewport ?? _surfaceSize;
      final imageSize = widget.imageSize ?? _surfaceSize;
      final rect = _iconRect;
      final overImage =
          rect != null &&
          viewport != null &&
          imageSize != null &&
          rect.top < imageSize.height - offset;
      if (overImage) {
        _lightForeground =
            widget.pixels?.useLightForeground(
              iconRect: rect,
              viewport: viewport,
              imageSize: imageSize,
              scrollOffset: offset,
              parallaxFactor: widget.parallaxFactor,
              background: theme.scaffoldBackgroundColor,
              previous: _lightForeground,
            ) ??
            (theme.brightness == Brightness.dark);
      } else {
        _lightForeground = null;
      }
      final light = _lightForeground ?? theme.brightness == Brightness.dark;
      final foreground = overImage
          ? (light ? ColorTokens.mathSurface : ColorTokens.poemInk)
          : theme.colorScheme.onSurface;
      final selected = light ? ColorTokens.mathYellow : ColorTokens.hintAmber;
      final outline = (light ? ColorTokens.poemInk : ColorTokens.mathSurface)
          .withValues(alpha: .8);
      const width = SpacingTokens.imageIconOutline;
      return IconTheme.merge(
        data: IconThemeData(
          shadows: overImage
              ? [
                  Shadow(color: outline, offset: const Offset(-width, 0)),
                  Shadow(color: outline, offset: const Offset(width, 0)),
                  Shadow(color: outline, offset: const Offset(0, -width)),
                  Shadow(color: outline, offset: const Offset(0, width)),
                ]
              : const [],
        ),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style:
                IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: foreground,
                  minimumSize: const Size.square(SpacingTokens.xxl),
                ).copyWith(
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return foreground.withValues(alpha: .38);
                    }
                    return states.contains(WidgetState.selected)
                        ? selected
                        : foreground;
                  }),
                ),
          ),
          child: child!,
        ),
      );
    },
  );
}
