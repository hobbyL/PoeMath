// lib/features/math/math_tab_page.dart
//
// 层级：features/math
// 职责：口算 tab 占位页，同时用于 Phase 0 视觉验证：
//       进入本 tab 时，主题应切换为"马卡龙童趣"，背景温白、主色薰衣草紫。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

class MathTabPage extends StatelessWidget {
  const MathTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('口算')),
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.calculate_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                '马卡龙 · 口算',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                '12 + 25 = ?',
                style: TextStyle(
                  fontSize: TypographyTokens.fsMathProblem,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                '本模块由 Phase 5 实现',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
