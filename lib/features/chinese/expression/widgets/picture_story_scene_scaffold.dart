import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_contrast.dart';

/// 题图作为顶部背景，内容向上覆盖；返回与页面操作始终固定在安全区内。
class PictureStorySceneScaffold extends ConsumerStatefulWidget {
  const PictureStorySceneScaffold({
    super.key,
    required this.image,
    required this.semanticLabel,
    required this.child,
    this.actions = const [],
  });

  final PictureStoryImage image;
  final String semanticLabel;
  final Widget child;
  final List<Widget> actions;

  @override
  ConsumerState<PictureStorySceneScaffold> createState() =>
      _PictureStorySceneScaffoldState();
}

class _PictureStorySceneScaffoldState
    extends ConsumerState<PictureStorySceneScaffold> {
  final _scroll = ScrollController();
  final _sceneKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final bytes = widget.image.isLocal
        ? ref
              .watch(pictureStoryImageBytesProvider(widget.image.value))
              .valueOrNull
        : null;
    final pixels = widget.image.isLocal && bytes == null
        ? null
        : ref
              .watch(
                pictureStorySceneContrastProvider((
                  image: widget.image,
                  imageBytes: bytes,
                  builtinScheme: widget.image.isLocal
                      ? null
                      : theme.colorScheme,
                )),
              )
              .valueOrNull;
    final header = bytes == null ? null : ByteData.sublistView(bytes);
    final aspectRatio = header == null
        ? 4 / 3
        : header.getUint32(16) / header.getUint32(20);
    final reduceMotion =
        media.disableAnimations ||
        media.accessibleNavigation ||
        !PageAnimationScope.enabledOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              // 按原图比例铺满宽度；横屏限制背景高度，键盘不改变题图尺寸。
              final imageHeight = math.min(
                media.size.height * .55,
                constraints.maxWidth / aspectRatio,
              );
              final parallaxFactor = reduceMotion ? 0.0 : .7;
              Widget adaptiveAction(Widget child) => _SceneToolbarAction(
                sceneKey: _sceneKey,
                scroll: _scroll,
                pixels: pixels,
                viewport: constraints.biggest,
                imageHeight: imageHeight,
                parallaxFactor: parallaxFactor,
                child: child,
              );
              return Stack(
                key: _sceneKey,
                children: [
                  SingleChildScrollView(
                    controller: _scroll,
                    child: Stack(
                      children: [
                        SizedBox(
                          height: imageHeight,
                          width: double.infinity,
                          child: ClipRect(
                            child: AnimatedBuilder(
                              animation: _scroll,
                              child: RepaintBoundary(
                                child: SizedBox.expand(
                                  child: PictureStoryImageView(
                                    image: widget.image,
                                    fit: BoxFit.cover,
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                              ),
                              builder: (context, child) {
                                final offset = _scroll.hasClients
                                    ? _scroll.offset.clamp(0.0, imageHeight)
                                    : 0.0;
                                return Transform.translate(
                                  offset: Offset(0, offset * parallaxFactor),
                                  child: child,
                                );
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: imageHeight),
                          child: ColoredCard(
                            color: theme.scaffoldBackgroundColor,
                            backgroundOpacity: 1,
                            borderRadius: BorderRadius.zero,
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            padding: const EdgeInsets.all(SpacingTokens.md),
                            child: SafeArea(top: false, child: widget.child),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: Row(
                          children: [
                            SizedBox(
                              width: kToolbarHeight,
                              child: Center(
                                child: adaptiveAction(
                                  BackButton(
                                    onPressed: () {
                                      final navigator = Navigator.of(context);
                                      if (navigator.canPop()) {
                                        navigator.pop();
                                      } else {
                                        GoRouter.maybeOf(context)?.go(
                                          AppRoutes.chineseSectionOf(
                                            'expression',
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            for (final action in widget.actions)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: SpacingTokens.xs,
                                ),
                                child: adaptiveAction(action),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SceneToolbarAction extends StatefulWidget {
  const _SceneToolbarAction({
    required this.sceneKey,
    required this.scroll,
    required this.pixels,
    required this.viewport,
    required this.imageHeight,
    required this.parallaxFactor,
    required this.child,
  });

  final GlobalKey sceneKey;
  final ScrollController scroll;
  final PictureStorySceneContrast? pixels;
  final Size viewport;
  final double imageHeight;
  final double parallaxFactor;
  final Widget child;

  @override
  State<_SceneToolbarAction> createState() => _SceneToolbarActionState();
}

class _SceneToolbarActionState extends State<_SceneToolbarAction> {
  Rect? _iconRect;
  bool? _lightForeground;
  bool _measurementPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureAfterLayout();
  }

  @override
  void didUpdateWidget(_SceneToolbarAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    _measureAfterLayout();
  }

  void _measureAfterLayout() {
    if (_measurementPending) return;
    _measurementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementPending = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      final scene = widget.sceneKey.currentContext?.findRenderObject();
      if (box is! RenderBox || scene is! RenderBox || !box.hasSize) return;
      final center = box.localToGlobal(
        box.size.center(Offset.zero),
        ancestor: scene,
      );
      final size = IconTheme.of(context).size ?? SpacingTokens.lg;
      final rect = Rect.fromCenter(center: center, width: size, height: size);
      if (rect != _iconRect) setState(() => _iconRect = rect);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.scroll,
    child: widget.child,
    builder: (context, child) {
      final theme = Theme.of(context);
      final offset = widget.scroll.hasClients ? widget.scroll.offset : 0.0;
      final rect = _iconRect;
      final overImage = rect != null && rect.top < widget.imageHeight - offset;
      if (overImage) {
        _lightForeground =
            widget.pixels?.useLightForeground(
              iconRect: rect,
              viewport: widget.viewport,
              imageHeight: widget.imageHeight,
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
