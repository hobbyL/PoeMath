import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';

/// Empty learning sections lead parents through the existing protected routes.
class ContentPreparationActions extends StatefulWidget {
  const ContentPreparationActions({super.key, required this.managementRoute});
  final String managementRoute;

  @override
  State<ContentPreparationActions> createState() =>
      _ContentPreparationActionsState();
}

class _ContentPreparationActionsState extends State<ContentPreparationActions> {
  bool _opening = false;

  Future<void> _prepare() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      await context.push(widget.managementRoute);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    children: [
      FilledButton.icon(
        onPressed: _opening ? null : _prepare,
        icon: const Icon(Icons.family_restroom_outlined),
        label: const Text('请家长准备内容'),
      ),
      TextButton(
        onPressed: () => context.go(AppRoutes.poemTab),
        child: const Text('先学诗词'),
      ),
    ],
  );
}
