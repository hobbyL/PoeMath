import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/picture_story_evaluation.dart';

/// 完成结果与历史共用已保存的反馈，不重新请求评价。
class PictureStoryFeedback extends StatelessWidget {
  const PictureStoryFeedback({
    super.key,
    required this.feedbackJson,
    this.legacyHeading = '练习记录',
    this.separated = false,
  });

  final String feedbackJson;
  final String legacyHeading;

  /// 独立详情中的点评分区；练习完成页继续使用原有内嵌布局。
  final bool separated;

  Widget _heading(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (separated) ...[
          const SizedBox(height: SpacingTokens.lg),
          const Divider(height: 1),
          const SizedBox(height: SpacingTokens.lg),
        ] else
          const SizedBox(height: SpacingTokens.md),
        Text(
          title,
          style: separated
              ? theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                )
              : theme.textTheme.titleMedium,
        ),
        SizedBox(height: separated ? SpacingTokens.md : SpacingTokens.sm),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      final decoded = jsonDecode(feedbackJson);
      if (decoded is! Map<String, dynamic>) return const SizedBox.shrink();
      if (decoded['version'] == 1 && decoded['source'] == 'vision') {
        final prompts = (decoded['prompts'] as List).cast<String>();
        final evaluation = PictureStoryEvaluation.parse(
          feedbackJson,
          answer: decoded['answer'] as String,
          questionCount: prompts.length,
        );
        final theme = Theme.of(context);
        Widget item(String title, PictureStoryFeedbackItem value) => Padding(
          padding: const EdgeInsets.only(top: SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · ${value.status.label}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: SpacingTokens.xs),
              if (value.evidence.isNotEmpty) ...[
                Text(
                  '你的原话：“${value.evidence}”',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
              ],
              Text(value.reason),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(context, 'AI 表达点评'),
            Text(evaluation.summary),
            for (final dimension in evaluation.dimensions)
              item(
                PictureStoryEvaluation.dimensionLabels[dimension.id]!,
                dimension,
              ),
            if (evaluation.questions.isNotEmpty)
              Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(
                    bottom: SpacingTokens.md,
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  title: const Text('逐题看看'),
                  children: [
                    for (final question in evaluation.questions)
                      item(prompts[int.parse(question.id) - 1], question),
                  ],
                ),
              ),
            if (evaluation.suggestions.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.lg),
              Text('试着这样改', style: theme.textTheme.titleMedium),
              for (final suggestion in evaluation.suggestions)
                Padding(
                  padding: const EdgeInsets.only(top: SpacingTokens.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '原句：${suggestion.original}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Text('建议：${suggestion.replacement}'),
                      const SizedBox(height: SpacingTokens.xs),
                      Text('原因：${suggestion.reason}'),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: SpacingTokens.sm),
            Text('根据图片与文字提供建议，不评价发音和语调。', style: theme.textTheme.bodySmall),
          ],
        );
      }
      final text = decoded['text'] as String?;
      final suggestion = decoded['suggestion'] as String?;
      final highlights = (decoded['highlights'] as List?)?.whereType<String>();
      final lines = [
        if (text != null) text,
        ...?highlights,
        if (suggestion != null) suggestion,
      ].map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
      if (lines.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            context,
            decoded['source'] == 'vision' ? 'AI 反馈' : legacyHeading,
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: Text(line),
            ),
        ],
      );
    } on Object {
      return const SizedBox.shrink();
    }
  }
}
