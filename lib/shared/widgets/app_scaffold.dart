// lib/shared/widgets/app_scaffold.dart
//
// 层级：shared/widgets
// 职责：可选的统一 Scaffold 包装，方便后续给业务页统一施加背景、SafeArea、错误边界等。
//       Phase 0 保留最基础实现，Phase 4+ 按需扩展。

import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: title == null
          ? null
          : AppBar(title: Text(title!), actions: actions),
      body: SafeArea(child: Padding(padding: padding, child: body)),
      floatingActionButton: floatingActionButton,
    );
  }
}
