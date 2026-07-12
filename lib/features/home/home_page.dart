// lib/features/home/home_page.dart
//
// 层级：features/home
// 职责：首页占位。Phase 6 完善（每日推荐、连续打卡、进度概览）。

import 'package:flutter/material.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/theme/design_tokens.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.home_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: SpacingTokens.md),
              Text('首页', style: theme.textTheme.headlineMedium),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                '本模块由 Phase 6 完善',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
