// lib/features/formula/study_hub_page.dart
//
// 层级：features/formula
// 职责：中央凸起"学习"入口占位页。Phase 6 会在此基础上扩展公式知识库。
//       Phase 0 仅用于验证 FAB 跳转链路。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

class StudyHubPage extends StatelessWidget {
  const StudyHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('学习')),
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.auto_stories,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                '学习中心',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                '公式知识库 / 学习指引',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                '本模块由 Phase 6 实现',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
