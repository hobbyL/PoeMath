// lib/features/profile/settings_page.dart
//
// 层级：features/profile
// 职责：集中管理应用主题风格与亮暗外观。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/theme_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subject = ref.watch(activeSubjectProvider);
    final mode = ref.watch(themeModeProvider);
    final isDark = switch (mode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(
                  SpacingTokens.radiusMedium,
                ),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                children: <Widget>[
                  _SettingsRow(
                    title: '主题风格',
                    trailing: SegmentedButton<AppSubject>(
                      expandedInsets: EdgeInsets.zero,
                      segments: const <ButtonSegment<AppSubject>>[
                        ButtonSegment<AppSubject>(
                          value: AppSubject.poem,
                          label: Text('诗词'),
                          icon: Icon(Icons.brush_rounded),
                        ),
                        ButtonSegment<AppSubject>(
                          value: AppSubject.math,
                          label: Text('口算'),
                          icon: Icon(Icons.calculate_rounded),
                        ),
                      ],
                      selected: <AppSubject>{subject},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<AppSubject> next) {
                        ref.read(activeSubjectProvider.notifier).state =
                            next.first;
                      },
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: SpacingTokens.md,
                    endIndent: SpacingTokens.md,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  _SettingsRow(
                    title: '外观',
                    trailing: Semantics(
                      label: '深色模式',
                      toggled: isDark,
                      child: Switch(
                        value: isDark,
                        onChanged: (bool enabled) {
                          ref.read(themeModeProvider.notifier).state =
                              enabled ? ThemeMode.dark : ThemeMode.light;
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldStack = constraints.maxWidth < 320 || textScale > 1.2;
        final titleWidget = Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );

        return ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SpacingTokens.minTapTarget + SpacingTokens.md,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            child: shouldStack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      titleWidget,
                      const SizedBox(height: SpacingTokens.sm),
                      SizedBox(
                        width: double.infinity,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: trailing,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      titleWidget,
                      const SizedBox(width: SpacingTokens.md),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: trailing,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
