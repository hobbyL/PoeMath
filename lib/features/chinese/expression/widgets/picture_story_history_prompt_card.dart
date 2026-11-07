import 'package:flutter/material.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';

String pictureStoryHistoryDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// 历史列表与单次详情展示同一份原题内容，保持图片贴边和顶部圆角。
class PictureStoryHistoryPromptCard extends StatelessWidget {
  const PictureStoryHistoryPromptCard({
    super.key,
    required this.prompt,
    this.showImage = true,
  });

  final PictureStoryPrompt? prompt;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: TypographyTokens.fsBodySmall,
    );
    final original = prompt;
    return ColoredCard(
      color: theme.colorScheme.primary,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (original != null && showImage)
            PictureStoryImageView(
              image: original.image,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SpacingTokens.radiusMedium),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  original?.title ?? '原题版本暂时无法读取',
                  style: theme.textTheme.titleMedium,
                ),
                if (original != null) ...[
                  const SizedBox(height: SpacingTokens.md),
                  Text('引导问题', style: theme.textTheme.titleMedium),
                  const SizedBox(height: SpacingTokens.sm),
                  for (final question in original.questions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                      child: Text(question, style: contentStyle),
                    ),
                  if (original.reference.isNotEmpty) ...[
                    const SizedBox(height: SpacingTokens.md),
                    Text('参考表达', style: theme.textTheme.titleMedium),
                    const SizedBox(height: SpacingTokens.sm),
                    Text(original.reference, style: contentStyle),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
