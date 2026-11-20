import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

enum PineInkScene { landscape, study, branch }

/// 松墨的淡墨底图；由前景决定尺寸，不增加页头或卡片高度。
/// 装饰不参与点击与语义，切换主题时保留正文的状态与滚动位置。
class PineInkSurface extends StatelessWidget {
  const PineInkSurface({
    super.key,
    required this.child,
    this.scene = PineInkScene.landscape,
    this.page = false,
  });

  final Widget child;
  final PineInkScene scene;
  final bool page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final branch = scene == PineInkScene.branch;
    return Stack(
      children: [
        if (theme.appearance.pine)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = math.min(
                        constraints.maxWidth *
                            (page ? .9 : (branch ? .42 : .65)),
                        SpacingTokens.xxl * (page ? 12 : 5),
                      );
                      return Align(
                        alignment: Alignment.bottomRight,
                        child: SizedBox(
                          width: width,
                          height: math.min(
                            constraints.maxHeight,
                            width * (branch ? .71 : .67),
                          ),
                          child: Image.asset(
                            switch (scene) {
                              PineInkScene.study =>
                                'assets/images/ink_study_overlay.png',
                              PineInkScene.landscape =>
                                'assets/images/ink_landscape_overlay.png',
                              PineInkScene.branch =>
                                'assets/images/ink_pine_branch.png',
                            },
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomRight,
                            cacheWidth: page ? 960 : 480,
                            color: theme.colorScheme.onSurface,
                            opacity: AlwaysStoppedAnimation(
                              dark ? .08 : (page ? .11 : .1),
                            ),
                            excludeFromSemantics: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}
