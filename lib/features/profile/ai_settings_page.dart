// lib/features/profile/ai_settings_page.dart
//
// 层级：features/profile
// 职责：AI 设置枢纽页 —— 设置→「AI 设置」的落地页。三个入口：
//       供应商设置（厂商配置与生效切换）、使用场景设置（场景绑定厂商）、
//       提示词设置（AI 讲解 system prompt 自定义）。
//       深链 AppRoutes.llmSettings 直达供应商设置（诗词/口算/出题页的
//       「去设置」入口），不经过本页。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/llm_provider_settings_page.dart';
import 'package:poemath/features/profile/llm_scenario_settings_page.dart';
import 'package:poemath/features/profile/prompt_settings_page.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsRepo = ref.watch(settingsRepositoryProvider);
    final providerCount = settingsRepo.llmProviders.length;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          AppTile(
            icon: Icons.dns_outlined,
            iconColor: theme.colorScheme.primary,
            title: '供应商设置',
            subtitle: providerCount == 0 ? '未配置' : '已配置 $providerCount 个服务',
            onTap: () => Navigator.push<void>(
              context,
              fadeSlideRoute(
                builder: (_) => const LlmProviderSettingsPage(),
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppTile(
            icon: Icons.alt_route_outlined,
            iconColor: theme.colorScheme.tertiary,
            title: '使用场景设置',
            subtitle: providerCount == 0 ? '请先配置供应商' : '为各功能指定厂商',
            onTap: () => Navigator.push<void>(
              context,
              fadeSlideRoute(
                builder: (_) => const LlmScenarioSettingsPage(),
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppTile(
            icon: Icons.edit_note_outlined,
            iconColor: theme.colorScheme.secondary,
            title: '提示词设置',
            subtitle: 'AI 讲解的内置提示词与自定义',
            onTap: () => Navigator.push<void>(
              context,
              fadeSlideRoute(
                builder: (_) => const PromptSettingsPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
