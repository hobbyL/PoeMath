// lib/features/profile/llm_provider_settings_page.dart
//
// 层级：features/profile
// 职责：LLM 供应商设置页（OpenAI 兼容，多厂商配置）——AI 设置枢纽的
//       「供应商设置」子页。上半部「我的配置」列表：点行切换生效配置；
//       新增 / 编辑 / 删除 / 测试 / 模型拉取全部进全屏编辑弹窗
//       （llm_provider_edit_dialog.dart）。API Key 只进系统安全存储，
//       本页不回显明文。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/llm_provider_display.dart';
import 'package:poemath/features/profile/widgets/llm_provider_edit_dialog.dart';

class LlmProviderSettingsPage extends ConsumerStatefulWidget {
  const LlmProviderSettingsPage({super.key});

  @override
  ConsumerState<LlmProviderSettingsPage> createState() =>
      _LlmProviderSettingsPageState();
}

class _LlmProviderSettingsPageState
    extends ConsumerState<LlmProviderSettingsPage> {
  @override
  void initState() {
    super.initState();
    // 迁移走异步：initState 内不得 await（FakeAsync 下 Hive 写链会挂起，
    // 且 setState-in-initState 会触发框架断言）。
    unawaited(_bootstrap());
  }

  /// 迁移旧单配置为多厂商结构（幂等，repo 侧并发去重）。不再自动进入
  /// 编辑——列表与编辑弹窗已解耦，迁移完成后列表自然可见。
  Future<void> _bootstrap() async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .migrateLegacyLlmConfigIfNeeded();
    } on Object catch (error) {
      AppLogger.e('供应商设置页初始化失败', tag: 'LlmSettings', error: error);
    }
    // 迁移产生新配置时列表须重建：SettingsRepository 非 ChangeNotifier，
    // build 里惰性读 Hive 不会自行感知（与 _setActive 同模式补 setState）。
    if (mounted) setState(() {});
  }

  /// 点列表行：切换生效配置（立即持久化，无需保存按钮）。
  Future<void> _setActive(String id) async {
    try {
      await ref.read(settingsRepositoryProvider).setLlmActiveProvider(id);
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

  /// 打开全屏编辑弹窗（config 为 null = 新增）并处理结果：
  /// 保存 / 删除后刷新列表并在应用级 Messenger 弹对应确认；
  /// 取消（null）无副作用。
  Future<void> _openEditDialog([LlmProviderConfig? config]) async {
    final result = await showLlmProviderEditDialog(context, config: config);
    if (!mounted) return;
    if (result == null) return;
    ref.invalidate(settingsRepositoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == LlmProviderEditResult.saved
              ? 'LLM 服务配置已保存'
              : 'LLM 服务配置已删除',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsRepo = ref.watch(settingsRepositoryProvider);
    final providers = settingsRepo.llmProviders;
    final activeId = settingsRepo.llmActiveProviderId;

    return Scaffold(
      appBar: AppBar(title: const Text('供应商设置')),
      body: ListView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          ColoredCard(
            color: theme.colorScheme.primary,
            width: double.infinity,
            child: Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Text(
                    '配置一个或多个 OpenAI 兼容服务（如 DeepSeek、通义千问），'
                    '供 AI 出题与讲解使用。点选列表中的配置使其生效；'
                    '不发送任何个人信息，API Key 仅保存在设备安全存储。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),

          // ============ 配置列表区 ============
          Text(
            '我的配置',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          if (providers.isEmpty)
            ColoredCard(
              color: theme.colorScheme.secondary,
              width: double.infinity,
              child: Text(
                '还没有 LLM 配置。点击下方「新增配置」填写供应商信息，'
                '即可添加第一个配置；也可以保存多个厂商配置，在列表中'
                '点选切换生效。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ColoredCard(
              color: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.xs,
                vertical: SpacingTokens.xs,
              ),
              width: double.infinity,
              // ListTile 在最近的 Material 祖先上绘制背景与水波纹，
              // ColoredCard 的 DecoratedBox 会遮挡；插入透明 Material
              // 让点击反馈落在卡片内部。
              child: Material(
                color: Colors.transparent,
                borderRadius:
                    BorderRadius.circular(SpacingTokens.radiusMedium),
                child: RadioGroup<String>(
                  groupValue: activeId,
                  onChanged: (value) {
                    if (value != null) _setActive(value);
                  },
                  child: Column(
                    children: [
                      for (final (index, config) in providers.indexed)
                        RadioListTile<String>(
                          value: config.id,
                          title: Text(providerDisplayName(index, config)),
                          subtitle:
                              Text(providerHostSummary(config.baseUrl)),
                          controlAffinity: ListTileControlAffinity.leading,
                          secondary: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: '编辑此配置',
                            onPressed: () => _openEditDialog(config),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: SpacingTokens.sm),
          OutlinedButton.icon(
            onPressed: () => _openEditDialog(),
            icon: const Icon(Icons.add_outlined),
            label: const Text('新增配置'),
          ),
        ],
      ),
    );
  }
}
