// lib/features/poem/poem_tab_page.dart
//
// 层级：features/poem
// 职责：诗词 tab 占位页，同时用于 Phase 0 视觉验证：
//       进入本 tab 时，主题应切换为"国风水墨"，背景宣纸色、主色墨绿。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

class PoemTabPage extends StatelessWidget {
  const PoemTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('诗词')),
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.menu_book_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                '国风水墨 · 诗词',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                '床前明月光，疑是地上霜',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                '本模块由 Phase 4 实现',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
