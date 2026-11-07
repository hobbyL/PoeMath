import 'dart:math' as math;

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
              return Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scroll,
                    child: Stack(
                      children: [
                        SizedBox(
                          height: imageHeight + SpacingTokens.radiusMedium,
                          width: double.infinity,
                          child: ClipRect(
                            child: AnimatedBuilder(
                              animation: _scroll,
                              child: RepaintBoundary(
                                child: ColoredBox(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: SpacingTokens.radiusMedium,
                                    ),
                                    child: SizedBox.expand(
                                      child: PictureStoryImageView(
                                        image: widget.image,
                                        fit: BoxFit.cover,
                                        borderRadius: BorderRadius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              builder: (context, child) {
                                final offset = _scroll.hasClients
                                    ? _scroll.offset.clamp(0.0, imageHeight)
                                    : 0.0;
                                return Transform.translate(
                                  offset: Offset(
                                    0,
                                    reduceMotion ? 0 : offset * .7,
                                  ),
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
                      child: IconButtonTheme(
                        data: IconButtonThemeData(
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.surface,
                            foregroundColor: theme.colorScheme.onSurface,
                            disabledBackgroundColor: theme.colorScheme.surface,
                            disabledForegroundColor: theme.colorScheme.onSurface
                                .withValues(alpha: .38),
                            minimumSize: const Size.square(SpacingTokens.xxl),
                          ),
                        ),
                        child: SizedBox(
                          height: kToolbarHeight,
                          child: Row(
                            children: [
                              SizedBox(
                                width: kToolbarHeight,
                                child: Center(
                                  child: BackButton(
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
                              const Spacer(),
                              for (final action in widget.actions)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: SpacingTokens.xs,
                                  ),
                                  child: action,
                                ),
                            ],
                          ),
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
