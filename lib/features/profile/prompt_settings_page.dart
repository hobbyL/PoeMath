// lib/features/profile/prompt_settings_page.dart
//
// 层级：features/profile
// 职责：AI 讲解提示词设置页 —— 诗词讲解与口算解析两个 system prompt
//       的查看、编辑与一键恢复默认。仅 system prompt 可编辑；user prompt
//       为程序拼装（隐私载荷最小化），不在此页面范围。
//
// 语义（与 SettingsRepository 对齐）：
// - 编辑框初始展示「当前生效内容」= 覆盖值 ?? 内置默认常量；
// - 保存：trim 后为空 → 删 key（恢复默认）；超 2000 字符 → 拒绝；
// - 恢复默认：先弹确认弹层只读展示内置默认全文（用户改坏后可先看看
//   原来是什么样再决定），确认后删 key 回落编译期常量。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/prompts/explain_prompt_defaults.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

/// 提示词长度上限：超出拒绝保存（防误粘贴巨量文本撑爆请求体）。
const int kExplainPromptMaxLength = 2000;

class PromptSettingsPage extends ConsumerStatefulWidget {
  const PromptSettingsPage({super.key});

  @override
  ConsumerState<PromptSettingsPage> createState() =>
      _PromptSettingsPageState();
}

class _PromptSettingsPageState extends ConsumerState<PromptSettingsPage> {
  late final TextEditingController _poemController;
  late final TextEditingController _mathController;

  /// 当前是否有用户覆盖（null = 内置默认态，恢复默认按钮禁用）。
  String? _poemOverride;
  String? _mathOverride;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(settingsRepositoryProvider);
    _poemOverride = repo.poemExplainPromptOverride;
    _mathOverride = repo.mathExplainPromptOverride;
    _poemController = TextEditingController(
      text: _poemOverride ?? kPoemExplainSystemPrompt,
    );
    _mathController = TextEditingController(
      text: _mathOverride ?? kMathExplainSystemPrompt,
    );
  }

  @override
  void dispose() {
    _poemController.dispose();
    _mathController.dispose();
    super.dispose();
  }

  /// 保存单个场景的提示词；空串语义 = 恢复默认（仓储内删 key）。
  Future<void> _save({
    required bool isPoem,
    required TextEditingController controller,
  }) async {
    final value = controller.text;
    if (value.trim().length > kExplainPromptMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('提示词超长，已取消保存'),
        ),
      );
      return;
    }
    final repo = ref.read(settingsRepositoryProvider);
    final trimmed = value.trim();
    if (isPoem) {
      await repo.setPoemExplainPrompt(value);
    } else {
      await repo.setMathExplainPrompt(value);
    }
    if (!mounted) return;
    setState(() {
      final defaultText =
          isPoem ? kPoemExplainSystemPrompt : kMathExplainSystemPrompt;
      if (trimmed.isEmpty) {
        // 空串语义 = 恢复默认：编辑框同步回默认全文（与重置按钮路径一致）。
        if (isPoem) {
          _poemOverride = null;
        } else {
          _mathOverride = null;
        }
        controller.text = defaultText;
      } else {
        if (isPoem) {
          _poemOverride = trimmed;
        } else {
          _mathOverride = trimmed;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(trimmed.isEmpty ? '已恢复默认' : '已保存')),
    );
  }

  /// 恢复默认：先弹确认弹层（只读展示内置默认全文），确认后删 key。
  Future<void> _reset({required bool isPoem}) async {
    final isCurrentDefault =
        isPoem ? _poemOverride == null : _mathOverride == null;
    if (isCurrentDefault) return;
    final defaultText =
        isPoem ? kPoemExplainSystemPrompt : kMathExplainSystemPrompt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isPoem ? '恢复诗词讲解默认' : '恢复口算解析默认'),
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
                  defaultText,
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

    final repo = ref.read(settingsRepositoryProvider);
    if (isPoem) {
      await repo.resetPoemExplainPrompt();
    } else {
      await repo.resetMathExplainPrompt();
    }
    if (!mounted) return;
    setState(() {
      if (isPoem) {
        _poemOverride = null;
        _poemController.text = kPoemExplainSystemPrompt;
      } else {
        _mathOverride = null;
        _mathController.text = kMathExplainSystemPrompt;
      }
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
        title: const Text('AI 讲解提示词'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '调整 AI 讲解的口吻与规则。只影响讲解风格，不改变发给 AI 的'
              '题目内容；改得不如意可随时恢复内置默认。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            _PromptSection(
              title: '诗词讲解',
              controller: _poemController,
              isCustom: _poemOverride != null,
              onSave: () => _save(
                isPoem: true,
                controller: _poemController,
              ),
              onReset: () => _reset(isPoem: true),
            ),
            const SizedBox(height: SpacingTokens.lg),
            _PromptSection(
              title: '口算解析',
              controller: _mathController,
              isCustom: _mathOverride != null,
              onSave: () => _save(
                isPoem: false,
                controller: _mathController,
              ),
              onReset: () => _reset(isPoem: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个场景的编辑区块：标题 + 状态标注 + 多行编辑框 + 操作按钮。
class _PromptSection extends StatelessWidget {
  const _PromptSection({
    required this.title,
    required this.controller,
    required this.isCustom,
    required this.onSave,
    required this.onReset,
  });

  final String title;
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
          const SizedBox(height: SpacingTokens.sm),
          TextField(
            controller: controller,
            maxLines: null,
            minLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: '输入讲解提示词',
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
