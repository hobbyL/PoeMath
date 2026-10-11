// lib/features/assistant/widgets/assistant_provider_switcher.dart
//
// 层级：features/assistant/widgets
// 职责：AI 助手 AppBar 的「模型 ｜ 供应商」展示 + 切换入口。点击弹两级选择层：
//       先选供应商（config，含「跟随默认」），再选该供应商下的模型；写入
//       assistant 场景的 provider+model 绑定（setScenarioSelection）。
// 复用：providerDisplayName / providerHostSummary 纯函数（与设置页一致）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/llm_provider_display.dart';

/// 「跟随默认」哨兵值（RadioGroup 不接受 null 选项值）。
const String _followDefaultValue = '__follow_default__';

/// AppBar 内「当前模型 ｜ 供应商」展示 + 切换器（绑定 [LlmScenario.assistant]）。
class AssistantProviderSwitcher extends ConsumerStatefulWidget {
  const AssistantProviderSwitcher({super.key});

  @override
  ConsumerState<AssistantProviderSwitcher> createState() =>
      _AssistantProviderSwitcherState();
}

class _AssistantProviderSwitcherState
    extends ConsumerState<AssistantProviderSwitcher> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.read(settingsRepositoryProvider);
    final providers = repo.llmProviders;
    final boundId = repo.providerIdForScenario(LlmScenario.assistant);
    final effectiveId = boundId ?? repo.llmActiveProviderId;

    var currentIndex = -1;
    for (final (i, p) in providers.indexed) {
      if (p.id == effectiveId) {
        currentIndex = i;
        break;
      }
    }
    final current = currentIndex >= 0 ? providers[currentIndex] : null;

    final String label;
    if (current == null) {
      label = '未配置模型';
    } else {
      // 场景选中 model 仅在确有绑定时适用，且须 ∈ 候选，否则回落默认 model。
      final selected = boundId != null
          ? repo.modelForScenario(LlmScenario.assistant)
          : null;
      final model = (selected != null && current.models.contains(selected))
          ? selected
          : current.model;
      final name = providerDisplayName(currentIndex, current);
      label = model.trim().isEmpty ? name : '${model.trim()} ｜ $name';
    }

    return InkWell(
      onTap: () => _pick(providers, boundId),
      borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.sm,
          vertical: SpacingTokens.xs,
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _pick(
    List<LlmProviderConfig> providers,
    String? boundId,
  ) async {
    if (providers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('尚未配置供应商，请到 AI 设置 → 供应商设置 添加'),
        ),
      );
      return;
    }
    final repo = ref.read(settingsRepositoryProvider);
    // 第一级：选供应商（含「跟随默认」）。
    final providerPick = await _pickProviderSheet(providers, boundId);
    if (providerPick == null) return;
    if (providerPick == _followDefaultValue) {
      await repo.setScenarioSelection(
        LlmScenario.assistant,
        providerId: null,
        model: null,
      );
      if (mounted) setState(() {});
      return;
    }
    final cfg = providers.firstWhere((p) => p.id == providerPick);
    final models = cfg.models.isNotEmpty
        ? cfg.models
        : (cfg.model.trim().isEmpty
            ? const <String>[]
            : <String>[cfg.model.trim()]);
    String? model;
    if (models.length <= 1) {
      model = models.isEmpty ? null : models.first;
    } else {
      // 第二级：选该供应商下的模型。
      final currentModel = boundId == providerPick
          ? repo.modelForScenario(LlmScenario.assistant)
          : null;
      model = await _pickModelSheet(cfg, models, currentModel);
      if (model == null) return; // 取消模型选择 = 不改动
    }
    try {
      await repo.setScenarioSelection(
        LlmScenario.assistant,
        providerId: providerPick,
        model: model,
      );
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配置不存在：${e.message ?? e}')),
        );
      }
    }
    if (mounted) setState(() {});
  }

  /// 第一级弹层：选供应商；返回 config.id / _followDefaultValue / null(取消)。
  Future<String?> _pickProviderSheet(
    List<LlmProviderConfig> providers,
    String? currentId,
  ) {
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
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: Text('选择供应商', style: theme.textTheme.titleMedium),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                    children: <Widget>[
                      RadioGroup<String>(
                        groupValue: currentId ?? _followDefaultValue,
                        onChanged: (v) => Navigator.pop(sheetContext, v),
                        child: Column(
                          children: <Widget>[
                            const RadioListTile<String>(
                              value: _followDefaultValue,
                              title: Text('跟随默认'),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            for (final (index, config) in providers.indexed)
                              RadioListTile<String>(
                                value: config.id,
                                title: Text(providerDisplayName(index, config)),
                                subtitle:
                                    Text(providerHostSummary(config.baseUrl)),
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
  }

  /// 第二级弹层：选 [cfg] 下的模型；返回模型名 / null(取消)。
  Future<String?> _pickModelSheet(
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
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: Text(
                    '选择模型 · ${providerDisplayName(0, cfg)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                    children: <Widget>[
                      RadioGroup<String>(
                        groupValue: selected,
                        onChanged: (v) => Navigator.pop(sheetContext, v),
                        child: Column(
                          children: <Widget>[
                            for (final m in models)
                              RadioListTile<String>(
                                value: m,
                                title: Text(m),
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
  }
}
