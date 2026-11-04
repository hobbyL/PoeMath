import 'package:flutter/material.dart';

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
    return AppEmptyState(
      icon: Icons.image_outlined,
      title: '内容暂时不可用',
      description: message,
      actions: [
        if (onRetry != null)
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
      ],
    );
  }
}
