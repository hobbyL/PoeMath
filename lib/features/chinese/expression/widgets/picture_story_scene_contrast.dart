import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';

/// 原图只解码为最长边 96px 的取样缓存；滚动时不解码、不截图。
final pictureStorySceneContrastProvider = FutureProvider.autoDispose
    .family<
      PictureStorySceneContrast,
      ({
        PictureStoryImage image,
        Uint8List? imageBytes,
        ColorScheme? builtinScheme,
      })
    >((ref, source) async {
      // 使用页面实际显示的字节，保持图片重试与局部 ProviderScope 覆盖一致。
      final bytes =
          source.imageBytes ??
          await PictureStoryIllustration.renderForVision(
            kind: source.image.value,
            scheme: source.builtinScheme!,
          );
      return PictureStorySceneContrast.decode(bytes);
    });

class PictureStorySceneContrast {
  PictureStorySceneContrast._(this._rgba, this.width, this.height);

  final Uint8List _rgba;
  final int width;
  final int height;

  static Future<PictureStorySceneContrast> decode(Uint8List png) async {
    final header = ByteData.sublistView(png);
    final width = header.getUint32(16);
    final height = header.getUint32(20);
    final scale = math.min(1.0, 96 / math.max(width, height));
    final codec = await ui.instantiateImageCodec(
      png,
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) throw const FormatException('无法读取题图像素');
        return PictureStorySceneContrast._(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          frame.image.width,
          frame.image.height,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// 将按钮下方 7×7 个采样点映射回裁切、视差平移和下拉放大后的原图。
  bool useLightForeground({
    required Rect iconRect,
    required Size viewport,
    required Size imageSize,
    required double scrollOffset,
    required double parallaxFactor,
    required Color background,
    bool? previous,
  }) {
    final imageHeight = imageSize.height;
    final sourceSize = Size(width.toDouble(), height.toDouble());
    final source = Alignment.center.inscribe(
      applyBoxFit(BoxFit.cover, sourceSize, imageSize).source,
      Offset.zero & sourceSize,
    );
    final hasBackdrop = imageSize.width < viewport.width;
    final backdropSource = Alignment.center.inscribe(
      applyBoxFit(
        BoxFit.cover,
        sourceSize,
        Size(viewport.width, imageHeight),
      ).source,
      Offset.zero & sourceSize,
    );
    final blurSigma =
        SpacingTokens.imageBackdropBlur * backdropSource.width / viewport.width;
    final stretch = math.max(0.0, -scrollOffset);
    final scale = 1 + stretch / imageHeight;
    final scaledWidth = imageSize.width * scale;
    final imageLeft = (viewport.width - scaledWidth) / 2;
    final backdropLeft = viewport.width * (1 - scale) / 2;
    final imageTop =
        -scrollOffset +
        scrollOffset.clamp(0.0, imageHeight) * parallaxFactor -
        stretch;
    var luminance = 0.0;
    const samples = 7;
    for (var row = 0; row < samples; row++) {
      for (var column = 0; column < samples; column++) {
        final x = iconRect.left + iconRect.width * (column + .5) / samples;
        final y = iconRect.top + iconRect.height * (row + .5) / samples;
        var color = background;
        if (y >= -math.max(0.0, scrollOffset) &&
            y < imageHeight - scrollOffset &&
            x >= 0 &&
            x < viewport.width) {
          int? index;
          if (x >= imageLeft && x < imageLeft + scaledWidth) {
            final pixelX =
                (source.left + (x - imageLeft) / scaledWidth * source.width)
                    .floor()
                    .clamp(0, width - 1);
            final pixelY =
                (source.top +
                        (y - imageTop) / (imageHeight * scale) * source.height)
                    .floor()
                    .clamp(0, height - 1);
            index = (pixelY * width + pixelX) * 4;
          }
          if (hasBackdrop && (index == null || _rgba[index + 3] < 255)) {
            color = Color.alphaBlend(
              _blurredPixel(
                backdropSource.left +
                    (x - backdropLeft) /
                        (viewport.width * scale) *
                        backdropSource.width,
                backdropSource.top +
                    (y - imageTop) /
                        (imageHeight * scale) *
                        backdropSource.height,
                crop: backdropSource,
                sigma: blurSigma,
              ),
              background,
            );
          }
          if (index != null) {
            color = Color.alphaBlend(
              Color.fromARGB(
                _rgba[index + 3],
                _rgba[index],
                _rgba[index + 1],
                _rgba[index + 2],
              ),
              color,
            );
          }
        }
        luminance += color.computeLuminance();
      }
    }
    luminance /= samples * samples;
    final lightContrast = _contrast(ColorTokens.mathSurface, luminance);
    final darkContrast = _contrast(ColorTokens.poemInk, luminance);
    final useLight = lightContrast > darkContrast;
    if (previous != null && previous != useLight) {
      final oldContrast = previous ? lightContrast : darkContrast;
      final newContrast = useLight ? lightContrast : darkContrast;
      if (newContrast < oldContrast * 1.15) return previous;
    }
    return useLight;
  }

  /// 在已有小图缓存上用固定 5×5 核估算模糊颜色，不重新解码或读取画面。
  Color _blurredPixel(
    double x,
    double y, {
    required Rect crop,
    required double sigma,
  }) {
    const weights = [1, 4, 6, 4, 1];
    var alpha = 0.0;
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    for (var row = 0; row < weights.length; row++) {
      for (var column = 0; column < weights.length; column++) {
        // 与 ImageFilter 的 clamp 一致，在裁切区域边缘重复边缘像素。
        final px = (x + (column - 2) * sigma)
            .floor()
            .clamp(
              crop.left.floor(),
              math.min(width - 1, crop.right.ceil() - 1),
            )
            .toInt();
        final py = (y + (row - 2) * sigma)
            .floor()
            .clamp(
              crop.top.floor(),
              math.min(height - 1, crop.bottom.ceil() - 1),
            )
            .toInt();
        final index = (py * width + px) * 4;
        final weight = weights[row] * weights[column];
        final weightedAlpha = _rgba[index + 3] * weight;
        alpha += weightedAlpha;
        red += _rgba[index] * weightedAlpha;
        green += _rgba[index + 1] * weightedAlpha;
        blue += _rgba[index + 2] * weightedAlpha;
      }
    }
    if (alpha == 0) return Colors.transparent;
    return Color.fromARGB(
      (alpha / 256).round(),
      (red / alpha).round(),
      (green / alpha).round(),
      (blue / alpha).round(),
    );
  }

  static double _contrast(Color color, double backgroundLuminance) {
    final foregroundLuminance = color.computeLuminance();
    return (math.max(foregroundLuminance, backgroundLuminance) + .05) /
        (math.min(foregroundLuminance, backgroundLuminance) + .05);
  }
}
