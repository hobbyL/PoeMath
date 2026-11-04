import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';

/// 完成结果与历史共用已保存的反馈，不重新请求评价。
class PictureStoryFeedback extends StatelessWidget {
  const PictureStoryFeedback({super.key, required this.feedbackJson});

  final String feedbackJson;

  @override
  Widget build(BuildContext context) {
    try {
      final decoded = jsonDecode(feedbackJson);
      if (decoded is! Map<String, dynamic>) return const SizedBox.shrink();
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
          const SizedBox(height: SpacingTokens.md),
          Text(
            decoded['source'] == 'vision' ? 'AI 反馈' : '练习反馈',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: SpacingTokens.xs),
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
