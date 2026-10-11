// lib/features/assistant/widgets/assistant_provider_switcher.dart
//
// 层级：features/assistant/widgets
// 职责：AI 助手 AppBar 的「模型 | 供应商」展示 + 切换入口。点击弹底部选择层，
//       为 assistant 场景绑定某条厂商配置（每条配置自带 baseUrl+model，故
//       「切换供应商」即切换其模型），或「跟随默认」。
// 说明：本项目一条 LlmProviderConfig = 供应商 + 固定模型，二者绑定；因此这里
//       不提供独立的「模型下拉」，切配置即切模型。
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

/// AppBar 内「当前模型 | 供应商」展示 + 切换器（绑定 [LlmScenario.assistant]）。
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
    final effectiveId = repo.providerIdForScenario(LlmScenario.assistant) ??
        repo.llmActiveProviderId;

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
      final model = current.model.trim();
      final name = providerDisplayName(currentIndex, current);
      label = model.isEmpty ? name : '$model ｜ $name';
    }

    return InkWell(
      onTap: () => _pick(providers, effectiveId),
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
    String? currentId,
  ) async {
    if (providers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('尚未配置供应商，请到 AI 设置 → 供应商设置 添加'),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
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
                    'AI 助手使用模型',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                    children: <Widget>[
                      RadioGroup<String>(
                        groupValue: currentId ?? _followDefaultValue,
                        onChanged: (value) =>
                            Navigator.pop(sheetContext, value),
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
                                subtitle: Text(
                                  '${config.model.trim().isEmpty ? '（未填模型）' : config.model} · ${providerHostSummary(config.baseUrl)}',
                                ),
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
    if (picked == null) return;
    final id = picked == _followDefaultValue ? null : picked;
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setProviderIdForScenario(LlmScenario.assistant, id);
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配置不存在：${e.message ?? e}')),
        );
      }
    }
    if (mounted) setState(() {});
  }
}
