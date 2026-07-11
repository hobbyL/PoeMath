// lib/features/profile/profile_page.dart
//
// 层级：features/profile
// 职责：个人中心占位页。Phase 0 特殊职责：提供 activeSubjectProvider / themeModeProvider
//       的手动切换入口，用于视觉验收。
//       - Segmented Toggle：切换 poem / math 学科主题
//       - Switch：深色模式开关（跟随系统 / 强制深色）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/theme_providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subject = ref.watch(activeSubjectProvider);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: <Widget>[
            // 学科主题切换
            Text('主题风格', style: theme.textTheme.titleLarge),
            const SizedBox(height: SpacingTokens.sm),
            SegmentedButton<AppSubject>(
              segments: const <ButtonSegment<AppSubject>>[
                ButtonSegment<AppSubject>(
                  value: AppSubject.poem,
                  label: Text('诗词 · 国风'),
                  icon: Icon(Icons.brush_rounded),
                ),
                ButtonSegment<AppSubject>(
                  value: AppSubject.math,
                  label: Text('口算 · 童趣'),
                  icon: Icon(Icons.emoji_emotions_rounded),
                ),
              ],
              selected: <AppSubject>{subject},
              onSelectionChanged: (Set<AppSubject> next) {
                ref.read(activeSubjectProvider.notifier).state = next.first;
              },
            ),

            const SizedBox(height: SpacingTokens.xl),

            // 深色模式切换
            Text('外观', style: theme.textTheme.titleLarge),
            const SizedBox(height: SpacingTokens.sm),
            SwitchListTile(
              title: const Text('深色模式'),
              subtitle: Text(_modeLabel(mode)),
              value: mode == ThemeMode.dark,
              onChanged: (bool on) {
                ref.read(themeModeProvider.notifier).state =
                    on ? ThemeMode.dark : ThemeMode.light;
              },
            ),
            TextButton(
              onPressed: () {
                ref.read(themeModeProvider.notifier).state = ThemeMode.system;
              },
              child: const Text('跟随系统'),
            ),

            const SizedBox(height: SpacingTokens.xl),
            Text('本模块由 Phase 6 完善', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '亮色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
}
