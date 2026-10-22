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
import 'package:poemath/data/providers/llm_runtime_providers.dart';
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
  LlmScenario.assistant: Icons.smart_toy_outlined,
};

class LlmScenarioSettingsPage extends ConsumerStatefulWidget {
  const LlmScenarioSettingsPage({super.key});

  @override
  ConsumerState<LlmScenarioSettingsPage> createState() =>
      _LlmScenarioSettingsPageState();
}

class _LlmScenarioSettingsPageState
    extends ConsumerState<LlmScenarioSettingsPage> {
  /// 应用场景选择：厂商 + 模型一次写入（null 厂商 = 跟随默认，连带清模型）。
  Future<void> _applyScenarioSelection(
    LlmScenario scenario, {
    required String? providerId,
    required String? model,
  }) async {
    try {
      await ref.read(settingsRepositoryProvider).setScenarioSelection(
            scenario,
            providerId: providerId,
            model: model,
          );
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
                      // 普通 ListTile（非 RadioGroup）：点「当前项」也要能继续
                      // 进入第二级选模型（RadioGroup 对未改变的值不触发）。
                      ListTile(
                        leading: Icon(
                          (currentId ?? _followDefaultValue) ==
                                  _followDefaultValue
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: (currentId ?? _followDefaultValue) ==
                                  _followDefaultValue
                              ? Theme.of(sheetContext).colorScheme.primary
                              : Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                        title: const Text('跟随默认'),
                        onTap: () => Navigator.pop(
                          sheetContext,
                          const _ScenarioPick(null),
                        ),
                      ),
                      for (final (index, config) in providers.indexed)
                        ListTile(
                          leading: Icon(
                            config.id == currentId
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: config.id == currentId
                                ? Theme.of(sheetContext).colorScheme.primary
                                : Theme.of(sheetContext)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          title: Text(providerDisplayName(index, config)),
                          subtitle: Text(providerHostSummary(config.baseUrl)),
                          onTap: () => Navigator.pop(
                            sheetContext,
                            _ScenarioPick(config.id),
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
    final providerId = selection.id;
    if (providerId == null) {
      await _applyScenarioSelection(scenario, providerId: null, model: null);
      return;
    }
    // 选了具体供应商：其有多个候选模型时，二级选模型。
    final cfg = providers.firstWhere((p) => p.id == providerId);
    final models = cfg.models.isNotEmpty
        ? cfg.models
        : (cfg.model.trim().isEmpty
            ? const <String>[]
            : <String>[cfg.model.trim()]);
    String? model;
    if (models.length <= 1) {
      model = models.isEmpty ? null : models.first;
    } else {
      final currentModel = currentId == providerId
          ? ref.read(settingsRepositoryProvider).modelForScenario(scenario)
          : null;
      model = await _pickModel(cfg, models, currentModel);
      if (model == null) return; // 取消模型选择 = 不改动
    }
    await _applyScenarioSelection(
      scenario,
      providerId: providerId,
      model: model,
    );
  }

  /// 二级弹层：选 [cfg] 下的模型；返回模型名 / null(取消)。
  Future<String?> _pickModel(
    LlmProviderConfig cfg,
    List<String> models,
    String? currentModel,
  ) {
    final selected = (currentModel != null && models.contains(currentModel))
        ? currentModel
        : (models.contains(cfg.model) ? cfg.model : models.first);
    return showModalBottomSheet<String>(
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
                    '选择模型',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.onSurface),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                    children: [
                      for (final m in models)
                        ListTile(
                          leading: Icon(
                            m == selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: m == selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(m),
                          onTap: () => Navigator.pop(sheetContext, m),
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
  }

  /// 场景行副标题：已绑定显示「厂商名 · 模型」，未绑定显示「跟随默认（厂商名）」。
  String _scenarioSummary(
    List<LlmProviderConfig> providers,
    String? scenarioId,
    String? activeId,
    String? scenarioModel,
  ) {
    if (scenarioId != null) {
      final index = providers.indexWhere((p) => p.id == scenarioId);
      if (index >= 0) {
        final cfg = providers[index];
        final model =
            (scenarioModel != null && cfg.models.contains(scenarioModel))
                ? scenarioModel
                : cfg.model;
        final name = providerDisplayName(index, cfg);
        return model.trim().isEmpty ? name : '$name · ${model.trim()}';
      }
    }
    final activeIndex = providers.indexWhere((p) => p.id == activeId);
    if (activeIndex >= 0) {
      return '跟随默认（${providerDisplayName(activeIndex, providers[activeIndex])}）';
    }
    return '跟随默认';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(llmSelectionVersionProvider);
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
                  settingsRepo.modelForScenario(scenario),
                ),
                onTap: () => _pickScenarioProvider(
                  scenario,
                  providers,
                  settingsRepo.providerIdForScenario(scenario),
                ),
              ),
              if (scenario != LlmScenario.values.last)
                const SizedBox(height: SpacingTokens.sm),
            ],
          ],
        ],
      ),
    );
  }
}
