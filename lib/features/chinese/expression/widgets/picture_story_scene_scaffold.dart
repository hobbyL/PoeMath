import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_action.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_contrast.dart';

/// 题图支持上滑视差、下拉等比放大；返回与页面操作始终固定在安全区内。
class PictureStorySceneScaffold extends ConsumerStatefulWidget {
  const PictureStorySceneScaffold({
    super.key,
    required this.image,
    required this.semanticLabel,
    required this.child,
    this.actions = const [],
    this.onBack,
  });

  final PictureStoryImage image;
  final String semanticLabel;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onBack;

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
    // 页面动画开关只控制转场与入场；跟随手势的视差、下拉反馈仍然可用。
    final reduceMotion = media.disableAnimations || media.accessibleNavigation;
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
              // 竖屏铺满宽度；横屏在高度上限内完整居中，键盘不改变题图尺寸。
              final imageHeight = math.min(
                media.size.height * .55,
                constraints.maxWidth / aspectRatio,
              );
              final imageWidth = media.orientation == Orientation.landscape
                  ? math.min(constraints.maxWidth, imageHeight * aspectRatio)
                  : constraints.maxWidth;
              final imageSize = Size(imageWidth, imageHeight);
              final parallaxFactor = reduceMotion ? 0.0 : .7;
              Widget adaptiveAction(Widget child) => PictureStoryImageAction(
                surfaceKey: _sceneKey,
                scroll: _scroll,
                pixels: pixels,
                viewport: constraints.biggest,
                imageSize: imageSize,
                parallaxFactor: parallaxFactor,
                child: child,
              );
              return Stack(
                key: _sceneKey,
                children: [
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(overscroll: false),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      physics: reduceMotion
                          ? const ClampingScrollPhysics()
                          : const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                      child: Stack(
                        children: [
                          SizedBox(
                            height: imageHeight,
                            width: double.infinity,
                            child: AnimatedBuilder(
                              animation: _scroll,
                              child: RepaintBoundary(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (imageWidth < constraints.maxWidth)
                                      ExcludeSemantics(
                                        child: IgnorePointer(
                                          child: ClipRect(
                                            child: ImageFiltered(
                                              imageFilter: ui.ImageFilter.blur(
                                                sigmaX: SpacingTokens
                                                    .imageBackdropBlur,
                                                sigmaY: SpacingTokens
                                                    .imageBackdropBlur,
                                                tileMode: TileMode.clamp,
                                              ),
                                              child: PictureStoryImageView(
                                                image: widget.image,
                                                preview: true,
                                                fit: BoxFit.cover,
                                                borderRadius: BorderRadius.zero,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    Center(
                                      child: SizedBox.fromSize(
                                        size: imageSize,
                                        child: PictureStoryImageView(
                                          key: const ValueKey(
                                            'picture-story-scene-image',
                                          ),
                                          image: widget.image,
                                          fit: BoxFit.cover,
                                          borderRadius: BorderRadius.zero,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              builder: (context, child) {
                                final offset = _scroll.hasClients
                                    ? _scroll.offset
                                    : 0.0;
                                final stretch = math.max(0.0, -offset);
                                return ClipRect(
                                  clipper: _SceneImageClipper(stretch),
                                  child: Transform.translate(
                                    offset: Offset(
                                      0,
                                      offset.clamp(0.0, imageHeight) *
                                          parallaxFactor,
                                    ),
                                    child: Transform.scale(
                                      scale: 1 + stretch / imageHeight,
                                      alignment: Alignment.bottomCenter,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
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
                                    onPressed:
                                        widget.onBack ??
                                        () {
                                          final navigator = Navigator.of(
                                            context,
                                          );
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

/// 下拉时允许图片向上放大到视口顶边，横向仍裁切在屏幕宽度内。
class _SceneImageClipper extends CustomClipper<Rect> {
  const _SceneImageClipper(this.stretch);

  final double stretch;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, -stretch, size.width, size.height + stretch);

  @override
  bool shouldReclip(_SceneImageClipper oldClipper) =>
      oldClipper.stretch != stretch;
}
