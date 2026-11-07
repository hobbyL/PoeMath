import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/color_tokens.dart';
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

  /// 将按钮下方 7×7 个采样点映射回 cover 裁切、视差平移后的原图。
  bool useLightForeground({
    required Rect iconRect,
    required Size viewport,
    required double imageHeight,
    required double scrollOffset,
    required double parallaxFactor,
    required Color background,
    bool? previous,
  }) {
    final output = Size(viewport.width, imageHeight);
    final sourceSize = Size(width.toDouble(), height.toDouble());
    final source = Alignment.center.inscribe(
      applyBoxFit(BoxFit.cover, sourceSize, output).source,
      Offset.zero & sourceSize,
    );
    final imageTop =
        -scrollOffset + scrollOffset.clamp(0.0, imageHeight) * parallaxFactor;
    var luminance = 0.0;
    const samples = 7;
    for (var row = 0; row < samples; row++) {
      for (var column = 0; column < samples; column++) {
        final x = iconRect.left + iconRect.width * (column + .5) / samples;
        final y = iconRect.top + iconRect.height * (row + .5) / samples;
        var color = background;
        if (y >= -scrollOffset &&
            y < imageHeight - scrollOffset &&
            x >= 0 &&
            x < viewport.width) {
          final pixelX = (source.left + x / output.width * source.width)
              .floor()
              .clamp(0, width - 1);
          final pixelY =
              (source.top + (y - imageTop) / output.height * source.height)
                  .floor()
                  .clamp(0, height - 1);
          final index = (pixelY * width + pixelX) * 4;
          color = Color.alphaBlend(
            Color.fromARGB(
              _rgba[index + 3],
              _rgba[index],
              _rgba[index + 1],
              _rgba[index + 2],
            ),
            background,
          );
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

  static double _contrast(Color color, double backgroundLuminance) {
    final foregroundLuminance = color.computeLuminance();
    return (math.max(foregroundLuminance, backgroundLuminance) + .05) /
        (math.min(foregroundLuminance, backgroundLuminance) + .05);
  }
}
