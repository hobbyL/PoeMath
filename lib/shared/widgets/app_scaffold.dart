// lib/shared/widgets/app_scaffold.dart
//
// 层级：shared/widgets
// 职责：兼容早期 title/padding 接口，页面背景统一委托 core/AppScaffold。

import 'package:flutter/material.dart';
import 'package:poemath/core/widgets/app_scaffold.dart' as core;

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    this.actions,
    required this.body,
    this.floatingActionButton,
    this.padding = EdgeInsets.zero,
  });

  final String? title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return core.AppScaffold(
      appBar: title == null
          ? null
          : AppBar(title: Text(title!), actions: actions),
      body: SafeArea(
        child: Padding(padding: padding, child: body),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
