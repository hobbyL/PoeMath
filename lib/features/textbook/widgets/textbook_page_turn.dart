import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_curl.dart';

const textbookPageTurnDuration = Duration(milliseconds: 480);

/// PageView 只负责手势和吸附，纸面使用原有 PDF 位图沿圆柱向外卷起。
class TextbookPageTurn extends StatelessWidget {
  const TextbookPageTurn({
    super.key,
    required this.controller,
    required this.index,
    required this.child,
    this.doublePage = false,
  });

  final PageController controller;
  final int index;
  final Widget child;
  final bool doublePage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final page = controller.hasClients
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        final distance = page - index;
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final incoming = distance < 0;
            final reduced = MediaQuery.disableAnimationsOf(context);
            final curl = TextbookPageCurl(
              size: constraints.biggest,
              progress: reduced
                  ? 0
                  : (incoming ? 1 + distance : distance).clamp(0.0, 1.0),
              // 封面单独翻动，内页从右页沿中央书脊翻到左侧。
              doublePage: doublePage && (incoming ? index > 1 : index > 0),
            );
            // 缓存、动画和静止始终保留同一 PDF 子树。
            return Opacity(
              opacity: distance <= -1 || distance >= 1 ? 0 : 1,
              child: Transform.translate(
                offset: reduced ? Offset.zero : Offset(distance * width, 0),
                child: ClipRect(
                  child: _CurlScope(
                    curl: curl,
                    incoming: incoming,
                    child: CustomPaint(
                      foregroundPainter: _CurlShadowPainter(
                        curl: curl,
                        incoming: incoming,
                        shadow: Theme.of(context).colorScheme.scrim,
                      ),
                      child: child!,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CurlScope extends InheritedWidget {
  const _CurlScope({
    required this.curl,
    required this.incoming,
    required super.child,
  });

  final TextbookPageCurl curl;
  final bool incoming;

  @override
  bool updateShouldNotify(_CurlScope oldWidget) =>
      oldWidget.curl != curl || oldWidget.incoming != incoming;
}

/// 借用 pdfrx 的 RawImage；不复制、不释放图片，也不另开 PDF 渲染器。
class TextbookCurlPageImage extends StatelessWidget {
  const TextbookCurlPageImage({
    super.key,
    required this.image,
    this.start = 0,
    this.end = 1,
    this.gutter = 0,
  });

  final RawImage image;
  final double start;
  final double end;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_CurlScope>();
    if (scope == null) return image;
    final curl = scope.curl;
    final center = (start + end) / 2;
    final source = Rect.fromCenter(
      center: Offset(
        curl.size.width * center + (center - 0.5) * gutter,
        curl.size.height / 2,
      ),
      width: image.width!,
      height: image.height!,
    );
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      foregroundPainter: _CurlImagePainter(
        curl: curl,
        incoming: scope.incoming,
        source: source,
        image: image.image!,
        paper: colors.surface,
        shadow: colors.scrim,
      ),
      child: ClipPath(
        clipper: _FlatPageClipper(curl, scope.incoming, source),
        child: image,
      ),
    );
  }
}

class _FlatPageClipper extends CustomClipper<Path> {
  const _FlatPageClipper(this.curl, this.incoming, this.source);

  final TextbookPageCurl curl;
  final bool incoming;
  final Rect source;

  @override
  Path getClip(Size size) {
    if (!curl.active) return Path()..addRect(Offset.zero & size);
    final path = incoming
        ? curl.revealed
        : source.right <= curl.spine
            ? (Path()..addRect(source))
            : curl.flatClip(source);
    return path.shift(-source.topLeft);
  }

  @override
  bool shouldReclip(_FlatPageClipper oldClipper) =>
      oldClipper.curl != curl ||
      oldClipper.incoming != incoming ||
      oldClipper.source != source;
}

class _CurlImagePainter extends CustomPainter {
  const _CurlImagePainter({
    required this.curl,
    required this.incoming,
    required this.source,
    required this.image,
    required this.paper,
    required this.shadow,
  });

  final TextbookPageCurl curl;
  final bool incoming;
  final Rect source;
  final ui.Image image;
  final Color paper;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (!curl.active) return;
    final backTexture =
        incoming && curl.doublePage && source.right <= curl.spine;
    if (incoming && !backTexture || !incoming && source.right <= curl.spine) {
      return;
    }
    final mesh = curl.meshFor(source, reverse: backTexture);
    canvas.save();
    canvas.translate(-source.left, -source.top);
    final shader = ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.low,
    );
    final texture = mesh.texture
        .map(
          (point) => Offset(
            (point.dx - source.left) / source.width * image.width,
            (point.dy - source.top) / source.height * image.height,
          ),
        )
        .toList();
    void draw(List<int> indices, {required bool back, required bool textured}) {
      if (indices.isEmpty) return;
      final colors = mesh.angles.map((angle) {
        final shade = back
            ? 0.06 + 0.18 * math.sin(angle).abs()
            : 0.20 * math.sin(angle).abs();
        // 纹理的中性光照系数，不改变原书颜色；纸背取主题表面色。
        return textured
            ? Color.from(
                alpha: 1,
                red: 1 - shade,
                green: 1 - shade,
                blue: 1 - shade,
              )
            : Color.lerp(paper, shadow, shade)!;
      }).toList();
      final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        mesh.positions,
        textureCoordinates: textured ? texture : null,
        colors: colors,
        indices: indices,
      );
      canvas.drawVertices(
        vertices,
        textured ? BlendMode.modulate : BlendMode.src,
        Paint()..shader = textured ? shader : null,
      );
      vertices.dispose();
    }

    if (backTexture) {
      // 下一展开页的左页就是正在翻动纸张的真实背面。
      draw(mesh.back, back: true, textured: true);
    } else {
      draw(mesh.front, back: false, textured: true);
      draw(mesh.back, back: true, textured: false);
    }
    shader.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurlImagePainter oldDelegate) =>
      oldDelegate.curl != curl ||
      oldDelegate.incoming != incoming ||
      oldDelegate.source != source ||
      oldDelegate.image != image ||
      oldDelegate.paper != paper ||
      oldDelegate.shadow != shadow;
}

class _CurlShadowPainter extends CustomPainter {
  const _CurlShadowPainter({
    required this.curl,
    required this.incoming,
    required this.shadow,
  });

  final TextbookPageCurl curl;
  final bool incoming;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (!incoming || !curl.active) return;
    final edge = curl
        .project(
          Offset(curl.fold + curl.radius * math.pi / 2, size.height / 2),
        )
        .position;
    final width = curl.radius * 1.4;
    if (width <= 0) return;
    final bounds = Rect.fromLTWH(edge.dx - width * 0.1, 0, width, size.height);
    canvas.save();
    canvas.clipPath(curl.revealed);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          colors: [
            shadow.withValues(alpha: 0.24),
            shadow.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurlShadowPainter oldDelegate) =>
      oldDelegate.curl != curl ||
      oldDelegate.incoming != incoming ||
      oldDelegate.shadow != shadow;
}
