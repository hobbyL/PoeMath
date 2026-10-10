// lib/features/profile/llm_scenario_settings_page.dart
//
// 层级：features/profile
// 职责：LLM 使用场景设置页 —— AI 设置枢纽的「使用场景设置」子页。
//       为每个功能场景（AI 出题 / 诗词讲解 / 口算解析）指定使用的
//       厂商配置，或跟随默认生效配置。厂商的增删改在供应商设置页完成，
//       本页只做场景 → 配置的绑定。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/llm_provider_display.dart';

/// 场景选择弹层「跟随默认」选项的哨兵值（RadioGroup 不接受 null 选项值）。
const String _followDefaultValue = '__follow_default__';

/// 场景选择弹层的返回值。用包装类区分「取消」（返回 null）与
/// 「选中跟随默认」（返回 id 为 null 的实例）。
final class _ScenarioPick {
  const _ScenarioPick(this.id);

  /// 选中的配置 id；null = 跟随默认。
  final String? id;
}

/// 场景行图标。
const Map<LlmScenario, IconData> _scenarioIcons = {
  LlmScenario.wordProblem: Icons.edit_note_outlined,
  LlmScenario.poemExplain: Icons.menu_book_outlined,
  LlmScenario.mathExplain: Icons.calculate_outlined,
};

class LlmScenarioSettingsPage extends ConsumerStatefulWidget {
  const LlmScenarioSettingsPage({super.key});

  @override
  ConsumerState<LlmScenarioSettingsPage> createState() =>
      _LlmScenarioSettingsPageState();
}

class _LlmScenarioSettingsPageState
    extends ConsumerState<LlmScenarioSettingsPage> {
  /// 点场景行：选择该场景使用的厂商（null = 跟随默认），点选即持久化。
  Future<void> _setScenarioProvider(
    LlmScenario scenario,
    String? id,
  ) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setProviderIdForScenario(scenario, id);
    } on ArgumentError catch (e) {
      // 竞态：列表在读取后被外部改写。刷新列表即可。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配置不存在：${e.message ?? e}')),
        );
      }
    }
    if (mounted) setState(() {});
  }

  /// 底部弹层：为 [scenario] 选择厂商。返回 null 表示取消。
  Future<void> _pickScenarioProvider(
    LlmScenario scenario,
    List<LlmProviderConfig> providers,
    String? currentId,
  ) async {
    final selection = await showModalBottomSheet<_ScenarioPick>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: Text(
                    '${scenario.label}使用厂商',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                    children: [
                      RadioGroup<String>(
                        groupValue: currentId ?? _followDefaultValue,
                        onChanged: (value) {
                          Navigator.pop(
                            sheetContext,
                            _ScenarioPick(
                              value == _followDefaultValue ? null : value,
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            const RadioListTile<String>(
                              value: _followDefaultValue,
                              title: Text('跟随默认'),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                            ),
                            for (final (index, config) in providers.indexed)
                              RadioListTile<String>(
                                value: config.id,
                                title: Text(providerDisplayName(index, config)),
                                subtitle: Text(providerHostSummary(config.baseUrl)),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selection == null) return;
    await _setScenarioProvider(scenario, selection.id);
  }

  /// 场景行副标题：已绑定显示厂商名，未绑定显示「跟随默认（厂商名）」。
  String _scenarioSummary(
    List<LlmProviderConfig> providers,
    String? scenarioId,
    String? activeId,
  ) {
    if (scenarioId != null) {
      final index = providers.indexWhere((p) => p.id == scenarioId);
      if (index >= 0) return providerDisplayName(index, providers[index]);
    }
    final activeIndex = providers.indexWhere((p) => p.id == activeId);
    if (activeIndex >= 0) {
      return '跟随默认（${providerDisplayName(activeIndex, providers[activeIndex])}）';
    }
    return '跟随默认';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsRepo = ref.watch(settingsRepositoryProvider);
    final providers = settingsRepo.llmProviders;
    final activeId = settingsRepo.llmActiveProviderId;

    return Scaffold(
      appBar: AppBar(title: const Text('使用场景设置')),
      body: ListView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          ColoredCard(
            color: theme.colorScheme.primary,
            width: double.infinity,
            child: Row(
              children: [
                Icon(
                  Icons.alt_route_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Text(
                    '为不同功能指定使用的厂商；未指定的场景跟随供应商设置中的'
                    '生效配置。厂商的添加与修改在「供应商设置」中完成。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),

          if (providers.isEmpty)
            ColoredCard(
              color: theme.colorScheme.secondary,
              width: double.infinity,
              child: Text(
                '还没有可用的厂商配置。请先到「供应商设置」添加配置，再回到'
                '这里为各场景指定使用的厂商。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            for (final scenario in LlmScenario.values) ...[
              AppTile(
                icon: _scenarioIcons[scenario]!,
                iconColor: theme.colorScheme.secondary,
                title: scenario.label,
                subtitle: _scenarioSummary(
                  providers,
                  settingsRepo.providerIdForScenario(scenario),
                  activeId,
                ),
                onTap: () => _pickScenarioProvider(
                  scenario,
                  providers,
                  settingsRepo.providerIdForScenario(scenario),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
