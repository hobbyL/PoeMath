import 'package:flutter/material.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class PictureStoryUnavailableView extends StatelessWidget {
  const PictureStoryUnavailableView({
    super.key,
    required this.message,
    this.onRetry,
  });
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: ResponsiveLayout.mediumBreakpoint),
          child: ColoredCard(
            color: theme.colorScheme.primary,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_search_outlined),
                const SizedBox(height: SpacingTokens.md),
                Text(message, textAlign: TextAlign.center),
                if (onRetry != null) ...[
                  const SizedBox(height: SpacingTokens.md),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
