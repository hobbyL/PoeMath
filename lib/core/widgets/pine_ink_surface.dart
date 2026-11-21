import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

enum PineInkScene { landscape, study, branch }

/// 主题底图；由前景决定尺寸，不增加页头或卡片高度。
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
    final appearance = theme.appearance;
    final hasSceneArt =
        page || appearance.pine || scene != PineInkScene.landscape;
    final asset = appearance.pine
        ? switch (scene) {
            PineInkScene.study => 'assets/images/ink_study_overlay.png',
            PineInkScene.landscape => appearance.pageImage,
            PineInkScene.branch => 'assets/images/ink_pine_branch.png',
          }
        : appearance.pageImage;
    return Stack(
      children: [
        if (page && appearance.playful)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PlayfulPageOrnament(
                      space: appearance.space,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (hasSceneArt)
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
                            key: const ValueKey('theme-page-art'),
                            asset,
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomRight,
                            cacheWidth: page ? 960 : 480,
                            color: appearance.pine
                                ? theme.colorScheme.onSurface
                                : null,
                            opacity: AlwaysStoppedAnimation(
                              switch (appearance.visualStyle) {
                                AppVisualStyle.pine =>
                                  dark ? .08 : (page ? .11 : .1),
                                AppVisualStyle.ink => dark ? .22 : .14,
                                AppVisualStyle.storybook => dark ? .1 : .13,
                                AppVisualStyle.space => dark ? .1 : .08,
                              },
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

/// 页角延续绘本的云朵或航行的轨迹；不占布局空间，也不覆盖正文。
class _PlayfulPageOrnament extends CustomPainter {
  const _PlayfulPageOrnament({required this.space, required this.color});

  final bool space;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = math.min(size.width * .8, SpacingTokens.xxl * 7);
    final height = width * .55;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width - width, size.height - height);
    final line = Paint()
      ..color = color.withValues(alpha: .08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (space) {
      canvas.translate(width * .7, height * .65);
      canvas.rotate(-.3);
      for (final scale in [.72, 1.1]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: width * scale,
            height: height * scale,
          ),
          line,
        );
      }
      final star = Paint()..color = color.withValues(alpha: .13);
      for (final position in [
        Offset(-width * .42, -height * .15),
        Offset(-width * .15, -height * .45),
        Offset(width * .3, height * .3),
      ]) {
        canvas.drawCircle(position, SpacingTokens.xs / 2, star);
      }
    } else {
      final cloud = Path()
        ..moveTo(0, height)
        ..cubicTo(
          0,
          height * .68,
          width * .2,
          height * .58,
          width * .3,
          height * .7,
        )
        ..cubicTo(
          width * .3,
          height * .2,
          width * .8,
          height * .2,
          width * .78,
          height * .62,
        )
        ..cubicTo(
          width,
          height * .5,
          width * 1.1,
          height * .65,
          width * 1.1,
          height,
        )
        ..close();
      canvas.drawPath(cloud, Paint()..color = color.withValues(alpha: .025));
      canvas.drawPath(cloud, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlayfulPageOrnament oldDelegate) =>
      oldDelegate.space != space || oldDelegate.color != color;
}
