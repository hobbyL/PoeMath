import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show OverScrollHeaderStretchConfiguration;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
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
    this.child,
    this.slivers,
    this.scrollController,
    this.scrollStorageKey,
    this.actions = const [],
    this.onBack,
    this.bottomNavigationBar,
  }) : assert((child == null) != (slivers == null));

  final PictureStoryImage image;
  final String semanticLabel;
  final Widget? child;
  final List<Widget>? slivers;
  final ScrollController? scrollController;
  final PageStorageKey<String>? scrollStorageKey;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final Widget? bottomNavigationBar;

  @override
  ConsumerState<PictureStorySceneScaffold> createState() =>
      _PictureStorySceneScaffoldState();
}

class _PictureStorySceneScaffoldState
    extends ConsumerState<PictureStorySceneScaffold> {
  late final _scroll = widget.scrollController ?? ScrollController();
  final _sceneKey = GlobalKey();

  @override
  void dispose() {
    if (widget.scrollController == null) _scroll.dispose();
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
        child: AppScaffold(
          backgroundScene: PineInkScene.study,
          bottomNavigationBar: widget.bottomNavigationBar,
          body: LayoutBuilder(
            builder: (context, constraints) {
              // 竖屏铺满宽度；横屏在高度上限内完整居中，键盘不改变题图尺寸。
              final contentImageHeight = math.min(
                media.size.height * .55,
                constraints.maxWidth / aspectRatio,
              );
              final collapsedHeight = kToolbarHeight + media.padding.top;
              final expandedHeight = math.max(
                contentImageHeight,
                collapsedHeight,
              );
              final imageWidth = media.orientation == Orientation.landscape
                  ? math.min(
                      constraints.maxWidth,
                      contentImageHeight * aspectRatio,
                    )
                  : constraints.maxWidth;
              final imageSize = Size(imageWidth, contentImageHeight);
              Widget adaptiveAction(Widget child) => PictureStoryImageAction(
                surfaceKey: _sceneKey,
                scroll: _scroll,
                pixels: pixels,
                viewport: constraints.biggest,
                imageSize: imageSize,
                parallaxFactor: 0,
                child: child,
              );
              final header = SliverPersistentHeader(
                pinned: true,
                delegate: _PictureStoryHeaderDelegate(
                  minExtent: collapsedHeight,
                  maxExtent: expandedHeight,
                  stretch: !reduceMotion,
                  builder: (context) => LayoutBuilder(
                    key: const ValueKey('picture-story-pinned-header'),
                    builder: (context, _) {
                      final stretch = _scroll.hasClients
                          ? math.max(0.0, -_scroll.offset)
                          : 0.0;
                      final imageScale = 1 + stretch / contentImageHeight;
                      return ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.hardEdge,
                          children: [
                            ColoredBox(color: theme.scaffoldBackgroundColor),
                            if (imageWidth < constraints.maxWidth)
                              Positioned.fill(
                                child: ExcludeSemantics(
                                  child: IgnorePointer(
                                    child: ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(
                                        sigmaX: SpacingTokens.imageBackdropBlur,
                                        sigmaY: SpacingTokens.imageBackdropBlur,
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
                            Align(
                              alignment: Alignment.topCenter,
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minWidth: imageSize.width,
                                maxWidth: imageSize.width,
                                minHeight: imageSize.height,
                                maxHeight: imageSize.height,
                                child: Transform.scale(
                                  scale: imageScale,
                                  alignment: Alignment.topCenter,
                                  child: SizedBox.fromSize(
                                    key: const ValueKey(
                                      'picture-story-scene-image',
                                    ),
                                    size: imageSize,
                                    child: PictureStoryImageView(
                                      image: widget.image,
                                      fit: BoxFit.cover,
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: media.padding.top,
                              left: 0,
                              child: SizedBox(
                                width: kToolbarHeight,
                                height: kToolbarHeight,
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
                            if (widget.actions.isNotEmpty)
                              Positioned(
                                top: media.padding.top,
                                right: 0,
                                height: kToolbarHeight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final action in widget.actions)
                                      adaptiveAction(action),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
              final content = widget.slivers != null
                  ? <Widget>[
                      SliverSafeArea(
                        top: false,
                        sliver: SliverPadding(
                          padding: const EdgeInsets.all(SpacingTokens.md),
                          sliver: SliverMainAxisGroup(slivers: widget.slivers!),
                        ),
                      ),
                    ]
                  : <Widget>[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: collapsedHeight),
                          child: ColoredCard(
                            key: const ValueKey('picture-story-body'),
                            color: theme.scaffoldBackgroundColor,
                            backgroundOpacity: 0,
                            borderRadius: BorderRadius.zero,
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            padding: const EdgeInsets.all(SpacingTokens.md),
                            child: SafeArea(top: false, child: widget.child!),
                          ),
                        ),
                      ),
                    ];
              return Stack(
                key: _sceneKey,
                fit: StackFit.expand,
                children: [
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(overscroll: false),
                    child: CustomScrollView(
                      key:
                          widget.scrollStorageKey ??
                          const ValueKey('picture-story-scroll-view'),
                      controller: _scroll,
                      physics: reduceMotion
                          ? const ClampingScrollPhysics()
                          : const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                      slivers: [header, ...content],
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

class _PictureStoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PictureStoryHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.stretch,
    required this.builder,
  });

  @override
  final double minExtent;

  @override
  final double maxExtent;

  final bool stretch;
  final WidgetBuilder builder;

  @override
  OverScrollHeaderStretchConfiguration? get stretchConfiguration =>
      stretch ? OverScrollHeaderStretchConfiguration() : null;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => builder(context);

  @override
  bool shouldRebuild(covariant _PictureStoryHeaderDelegate oldDelegate) =>
      minExtent != oldDelegate.minExtent ||
      maxExtent != oldDelegate.maxExtent ||
      stretch != oldDelegate.stretch ||
      builder != oldDelegate.builder;
}
