import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class PoemPracticeUnavailable extends StatelessWidget {
  const PoemPracticeUnavailable({
    super.key,
    required this.title,
    required this.missing,
  });

  final String title;
  final bool missing;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: AppEmptyState(
      icon: Icons.menu_book_outlined,
      title: missing ? '未找到这首诗词' : '暂无可练习的诗句',
      description: missing ? '内容可能已移除，请返回重新选择。' : '请选择有完整正文的诗词，或其他练习范围。',
      actions: [
        FilledButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              GoRouter.maybeOf(context)?.go(AppRoutes.chineseTab);
            }
          },
          child: const Text('返回选择诗词'),
        ),
      ],
    ),
  );
}
