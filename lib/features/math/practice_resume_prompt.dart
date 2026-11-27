import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';

/// true 续练，false 明确开始新练习，null 取消进入且保留草稿。
Future<bool?> choosePracticeResume(BuildContext context, String subject) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md,
          vertical: SpacingTokens.lg,
        ),
        title: Text('还有一组未完成的$subject'),
        content: const Text('继续上次题组，或放弃草稿后开始新的练习。已完成的答题记录会保留。'),
        actionsPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.md,
          0,
          SpacingTokens.md,
          SpacingTokens.md,
        ),
        actions: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextButton(
                    style: _actionStyle,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('暂时返回', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: TextButton(
                    style: _actionStyle,
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('开始新练习', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: FilledButton(
                    style: _actionStyle,
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('继续上次', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

const _actionStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, SpacingTokens.minTapTarget)),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(
      horizontal: SpacingTokens.xs,
      vertical: SpacingTokens.sm,
    ),
  ),
);
