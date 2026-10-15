// lib/features/profile/prompt_settings_page.dart
//
// 层级：features/profile
// 职责：AI 提示词设置页 —— 诗词讲解、口算解析、助手人设三份 system prompt
//       的查看、编辑与一键恢复默认。仅 system prompt 可编辑；user prompt
//       为程序拼装（隐私载荷最小化），不在此页面范围。
//
// 语义（与 SettingsRepository 对齐）：
// - 编辑框初始展示「当前生效内容」= 覆盖值 ?? 内置默认常量；
// - 保存：trim 后为空 → 删 key（恢复默认）；超 [kPromptMaxLength] → 拒绝；
// - 恢复默认：先弹确认弹层只读展示内置默认全文（用户改坏后可先看看
//   原来是什么样再决定），确认后删 key 回落编译期常量。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/prompts/assistant_prompt_defaults.dart';
import 'package:poemath/core/prompts/explain_prompt_defaults.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 提示词长度上限：超出拒绝保存（防误粘贴巨量文本撑爆请求体）。
///
/// 三个场景（诗词讲解 / 口算解析 / 助手人设）共用同一上限：
/// 内置默认值都在 1.2k 字符以内，2000 已留足编辑余量，且仓储层无校验，
/// UI 是唯一闸口，统一口径可避免「换个区块就能绕过」。
const int kPromptMaxLength = 2000;

/// 可编辑的提示词场景。
///
/// 三个场景的读写、默认值与文案差异集中在此，页面主体只按枚举分发，
/// 避免三份几乎相同的分支代码各自漂移。
enum _PromptScene {
  poemExplain(
    title: '诗词讲解',
    hintText: '输入讲解提示词',
    resetTitle: '恢复诗词讲解默认',
    explanation: '调整诗词讲解的口吻与规则。',
  ),
  mathExplain(
    title: '口算解析',
    hintText: '输入解析提示词',
    resetTitle: '恢复口算解析默认',
    explanation: '调整口算解析的口吻与规则。',
  ),
  assistant(
    title: 'AI 助手人设',
    hintText: '输入助手人设提示词',
    resetTitle: '恢复助手人设默认',
    explanation: '调整 AI 助手的身份设定、说话风格与行为边界。'
        '影响助手对话与工具调用时的自我认知。',
  );

  const _PromptScene({
    required this.title,
    required this.hintText,
    required this.resetTitle,
    required this.explanation,
  });

  final String title;
  final String hintText;
  final String resetTitle;
  final String explanation;

  /// 内置默认全文。
  String get defaultText => switch (this) {
        _PromptScene.poemExplain => kPoemExplainSystemPrompt,
        _PromptScene.mathExplain => kMathExplainSystemPrompt,
        _PromptScene.assistant => kAssistantSystemPrompt,
      };

  /// 当前生效内容：用户覆盖值 ?? 内置默认。
  String currentText(SettingsRepository repo) => switch (this) {
        _PromptScene.poemExplain =>
          repo.poemExplainPromptOverride ?? kPoemExplainSystemPrompt,
        _PromptScene.mathExplain =>
          repo.mathExplainPromptOverride ?? kMathExplainSystemPrompt,
        _PromptScene.assistant =>
          repo.assistantPromptOverride ?? kAssistantSystemPrompt,
      };

  /// 当前是否有用户覆盖（null = 内置默认态）。
  String? overrideOf(SettingsRepository repo) => switch (this) {
        _PromptScene.poemExplain => repo.poemExplainPromptOverride,
        _PromptScene.mathExplain => repo.mathExplainPromptOverride,
        _PromptScene.assistant => repo.assistantPromptOverride,
      };

  Future<void> save(SettingsRepository repo, String value) => switch (this) {
        _PromptScene.poemExplain => repo.setPoemExplainPrompt(value),
        _PromptScene.mathExplain => repo.setMathExplainPrompt(value),
        _PromptScene.assistant => repo.setAssistantPrompt(value),
      };

  Future<void> reset(SettingsRepository repo) => switch (this) {
        _PromptScene.poemExplain => repo.resetPoemExplainPrompt(),
        _PromptScene.mathExplain => repo.resetMathExplainPrompt(),
        _PromptScene.assistant => repo.resetAssistantPrompt(),
      };
}

class PromptSettingsPage extends ConsumerStatefulWidget {
  const PromptSettingsPage({super.key});

  @override
  ConsumerState<PromptSettingsPage> createState() =>
      _PromptSettingsPageState();
}

class _PromptSettingsPageState extends ConsumerState<PromptSettingsPage> {
  late final Map<_PromptScene, TextEditingController> _controllers;

  /// 各场景当前是否有用户覆盖（null = 内置默认态，恢复默认按钮禁用）。
  late final Map<_PromptScene, String?> _overrides;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(settingsRepositoryProvider);
    _controllers = {
      for (final scene in _PromptScene.values)
        scene: TextEditingController(text: scene.currentText(repo)),
    };
    _overrides = {
      for (final scene in _PromptScene.values) scene: scene.overrideOf(repo),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 保存单个场景的提示词；空串语义 = 恢复默认（仓储内删 key）。
  Future<void> _save(_PromptScene scene) async {
    final controller = _controllers[scene]!;
    final value = controller.text;
    if (value.trim().length > kPromptMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${scene.title}提示词超长，已取消保存'),
        ),
      );
      return;
    }
    final repo = ref.read(settingsRepositoryProvider);
    final trimmed = value.trim();
    await scene.save(repo, value);
    if (!mounted) return;
    setState(() {
      if (trimmed.isEmpty) {
        // 空串语义 = 恢复默认：编辑框同步回默认全文（与重置按钮路径一致）。
        _overrides[scene] = null;
        controller.text = scene.defaultText;
      } else {
        _overrides[scene] = trimmed;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(trimmed.isEmpty ? '已恢复默认' : '已保存')),
    );
  }

  /// 恢复默认：先弹确认弹层（只读展示内置默认全文），确认后删 key。
  Future<void> _reset(_PromptScene scene) async {
    if (_overrides[scene] == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(scene.resetTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('内置默认提示词如下，确认后将替换当前内容：'),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  scene.defaultText,
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await scene.reset(ref.read(settingsRepositoryProvider));
    if (!mounted) return;
    setState(() {
      _overrides[scene] = null;
      _controllers[scene]!.text = scene.defaultText;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复默认')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 提示词设置'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '调整 AI 的口吻与人设。只影响表达风格，不改变发给 AI 的'
              '题目内容与隐私载荷；改得不如意可随时恢复内置默认。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final scene in _PromptScene.values) ...[
              const SizedBox(height: SpacingTokens.lg),
              _PromptSection(
                title: scene.title,
                explanation: scene.explanation,
                hintText: scene.hintText,
                controller: _controllers[scene]!,
                isCustom: _overrides[scene] != null,
                onSave: () => _save(scene),
                onReset: () => _reset(scene),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单个场景的编辑区块：标题 + 状态标注 + 说明 + 多行编辑框 + 操作按钮。
class _PromptSection extends StatelessWidget {
  const _PromptSection({
    required this.title,
    required this.explanation,
    required this.hintText,
    required this.controller,
    required this.isCustom,
    required this.onSave,
    required this.onReset,
  });

  final String title;
  final String explanation;
  final String hintText;
  final TextEditingController controller;
  final bool isCustom;
  final VoidCallback onSave;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                isCustom ? '已自定义' : '内置默认',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isCustom
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          TextField(
            controller: controller,
            maxLines: null,
            minLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(SpacingTokens.radiusSmall),
              ),
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: SpacingTokens.sm),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  // 已是默认态时禁用（design.md：重置仅对自定义值有意义）。
                  onPressed: isCustom ? onReset : null,
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('恢复默认'),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
