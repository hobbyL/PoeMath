import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/domain/poem_practice_details.dart';

/// 同时显示原文和实际作答，标记按顺序未匹配的字，避免只给总分。
class PoemAnswerDifference extends StatelessWidget {
  const PoemAnswerDifference({
    super.key,
    required this.expected,
    required this.answer,
    this.answerLabel = '我的作答',
  });
  final String expected;
  final String answer;
  final String answerLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = normalizePoemAnswer(expected).characters.toList();
    final b = normalizePoemAnswer(answer).characters.toList();
    final dp = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1] + 1
            : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
      }
    }
    final matchedA = <int>{};
    final matchedB = <int>{};
    var i = a.length;
    var j = b.length;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        matchedA.add(--i);
        matchedB.add(--j);
      } else if (dp[i - 1][j] >= dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    final missing = [
      for (var k = 0; k < a.length; k++)
        if (!matchedA.contains(k)) a[k],
    ].join();
    final extra = [
      for (var k = 0; k < b.length; k++)
        if (!matchedB.contains(k)) b[k],
    ].join();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('原文：$expected', style: theme.textTheme.bodyMedium),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          '$answerLabel：${answer.isEmpty ? '未作答' : answer}',
          style: theme.textTheme.bodyMedium,
        ),
        if (missing.isNotEmpty || extra.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.xs),
          Text(
            [
              if (missing.isNotEmpty) '未匹配原文字：$missing',
              if (extra.isNotEmpty) '作答中未匹配字：$extra',
            ].join('\n'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ] else
          Text('文字一致（忽略标点与空格）', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
