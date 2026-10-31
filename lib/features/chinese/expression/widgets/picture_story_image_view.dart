import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';

/// 详情按图片自身比例完整显示；列表可由外层约束裁切成缩略图。
class PictureStoryImageView extends ConsumerWidget {
  const PictureStoryImageView({
    super.key,
    required this.image,
    this.preview = false,
    this.fit = BoxFit.contain,
    this.borderRadius,
  });
  final PictureStoryImage image;
  final bool preview;
  final BoxFit fit;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!image.isLocal) {
      return PictureStoryIllustration(
        kind: image.value,
        borderRadius: borderRadius,
      );
    }
    final bytes = ref.watch(pictureStoryImageBytesProvider(image.value));
    return bytes.when(
      loading: () => _placeholder(context, loading: true),
      error: (error, stackTrace) => _placeholder(context, ref: ref),
      data: (data) {
        final header = ByteData.sublistView(data);
        return AspectRatio(
          aspectRatio: header.getUint32(16) / header.getUint32(20),
          child: ClipRRect(
            borderRadius: borderRadius ??
                BorderRadius.circular(SpacingTokens.radiusMedium),
            child: Image.memory(
              data,
              fit: fit,
              width: double.infinity,
              semanticLabel: '题目图片',
              errorBuilder: (context, error, stackTrace) =>
                  _placeholder(context, ref: ref),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder(
    BuildContext context, {
    bool loading = false,
    WidgetRef? ref,
  }) {
    final theme = Theme.of(context);
    final label = loading ? '正在加载图片' : '图片暂时无法显示';
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius:
            borderRadius ?? BorderRadius.circular(SpacingTokens.radiusMedium),
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: preview
              ? Tooltip(
                  message: label,
                  child: Icon(Icons.image_outlined, semanticLabel: label),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.image_outlined),
                        const SizedBox(height: SpacingTokens.sm),
                        Text(label, textAlign: TextAlign.center),
                        if (!loading) ...[
                          const SizedBox(height: SpacingTokens.xs),
                          const Text(
                            '请在题目编辑中重新选择图片',
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: () => ref?.invalidate(
                              pictureStoryImageBytesProvider(image.value),
                            ),
                            child: const Text('重新加载'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
