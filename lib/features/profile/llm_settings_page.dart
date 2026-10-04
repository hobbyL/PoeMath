// lib/features/profile/llm_settings_page.dart
//
// 层级：features/profile
// 职责：应用题 AI 出题的 LLM 服务设置页（OpenAI 兼容）。
//       API Key 只进系统安全存储，页面不回显明文；留空保存 = 保留旧 Key。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

/// 连接测试的行内反馈状态。
enum _TestState { idle, loading, success, failure }

class LlmSettingsPage extends ConsumerStatefulWidget {
  const LlmSettingsPage({super.key});

  @override
  ConsumerState<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends ConsumerState<LlmSettingsPage> {
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// 是否已存 API Key（决定占位提示文案；不回显明文）。
  bool _hasStoredKey = false;

  /// 模型下拉候选；null = 拉取失败或为空，退化手填。
  List<String>? _modelOptions;

  _TestState _testState = _TestState.idle;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final settingsRepo = ref.read(settingsRepositoryProvider);
    _baseUrlController.text = settingsRepo.llmBaseUrl;
    _modelController.text = settingsRepo.llmModel;
    _loadStoredKey();
    _loadModels();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredKey() async {
    final key = await ref.read(secureCredentialStoreProvider).readLlmApiKey();
    if (mounted) {
      setState(() => _hasStoredKey = key != null && key.trim().isNotEmpty);
    }
  }

  Future<void> _loadModels() async {
    final config = await ref.read(settingsRepositoryProvider).readLlmConfig();
    if (config == null) return;
    final client = LlmClient();
    try {
      final models = await client.listModels(config);
      if (mounted) {
        setState(() => _modelOptions = models.isEmpty ? null : models);
      }
    } on LlmException {
      // 拉取失败退化手填，不打断页面。
      if (mounted) setState(() => _modelOptions = null);
    } finally {
      client.close();
    }
  }

  /// 用当前表单值构造配置（测试连接用；Key 留空时不含已存 Key，
  /// 由 [_testConnection] 单独补齐，不写存储）。
  LlmConfig? _buildConfigFromForm() {
    final base = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (base.isEmpty || model.isEmpty) return null;
    return LlmConfig(
      baseUrl: base,
      apiKey: _apiKeyController.text.trim(),
      model: model,
    );
  }

  Future<void> _testConnection() async {
    final config = _buildConfigFromForm();
    if (config == null) {
      setState(() {
        _testState = _TestState.failure;
        _testMessage = '请先填写服务地址和模型名';
      });
      return;
    }
    // 测试连接需要已存的 Key 时从安全存储读取。
    var configToTest = config;
    if (_apiKeyController.text.trim().isEmpty && _hasStoredKey) {
      final stored =
          await ref.read(secureCredentialStoreProvider).readLlmApiKey();
      configToTest = LlmConfig(
        baseUrl: config.baseUrl,
        apiKey: stored ?? '',
        model: config.model,
      );
    }
    setState(() {
      _testState = _TestState.loading;
      _testMessage = null;
    });
    final client = LlmClient();
    try {
      await client.testConnection(configToTest);
      if (mounted) {
        setState(() {
          _testState = _TestState.success;
          _testMessage = '连接成功，模型可用';
        });
      }
    } on LlmException catch (e) {
      if (mounted) {
        setState(() {
          _testState = _TestState.failure;
          _testMessage = e.message;
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _testState = _TestState.failure;
          _testMessage = '服务地址无效：${e.message}';
        });
      }
    } finally {
      client.close();
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 留空保存 = 保留旧 Key：显式读回安全存储中的 Key。
    var apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty && _hasStoredKey) {
      final stored =
          await ref.read(secureCredentialStoreProvider).readLlmApiKey();
      apiKey = stored ?? '';
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    try {
      await settingsRepo.saveLlmConfig(
        baseUrl: _baseUrlController.text.trim(),
        model: _modelController.text.trim(),
        apiKey: apiKey,
      );
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('服务地址无效：${e.message}')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _hasStoredKey = apiKey.isNotEmpty);
    _apiKeyController.clear();
    ref.invalidate(settingsRepositoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('LLM 服务配置已保存')),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 LLM 配置'),
        content: const Text('将删除服务地址、模型名与已保存的 API Key，'
            '应用题生成功能将不可用。题库中已有的题目不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(settingsRepositoryProvider).deleteLlmConfig();
    if (!mounted) return;
    setState(() {
      _baseUrlController.clear();
      _modelController.clear();
      _apiKeyController.clear();
      _hasStoredKey = false;
      _modelOptions = null;
    });
    ref.invalidate(settingsRepositoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('LLM 服务配置已删除')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured =
        _baseUrlController.text.trim().isNotEmpty &&
        _modelController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 出题设置')),
      body: Form(
        key: _formKey,
        child: ListView(
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
                      '用于「应用题 AI 出题」。应用把题目数字结构发送给您配置的 '
                      'OpenAI 兼容服务，返回题面经本地校验后由家长确认入库；'
                      '不发送任何个人信息，API Key 仅保存在设备安全存储。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            TextFormField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: '服务地址（Base URL）',
                hintText: '例如 https://api.example.com/v1',
                prefixIcon: Icon(Icons.link_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return '请填写服务地址';
                return null;
              },
            ),
            const SizedBox(height: SpacingTokens.md),

            // 模型：下拉可用时选择，否则手填
            if (_modelOptions != null)
              DropdownButtonFormField<String>(
                initialValue: _modelController.text.trim().isEmpty ||
                        !_modelOptions!.contains(_modelController.text.trim())
                    ? null
                    : _modelController.text.trim(),
                decoration: const InputDecoration(
                  labelText: '模型',
                  prefixIcon: Icon(Icons.model_training_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final model in _modelOptions!)
                    DropdownMenuItem(value: model, child: Text(model)),
                ],
                onChanged: (value) {
                  setState(() => _modelController.text = value ?? '');
                },
              )
            else
              TextFormField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: '模型名',
                  hintText: '服务未返回模型列表，请手动填写',
                  prefixIcon: Icon(Icons.model_training_outlined),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return '请填写模型名';
                  return null;
                },
              ),
            const SizedBox(height: SpacingTokens.md),

            TextFormField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API Key（可选）',
                hintText: _hasStoredKey ? '已设置，留空保持不变' : '无鉴权服务可留空',
                prefixIcon: const Icon(Icons.key_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),

            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存配置'),
            ),
            const SizedBox(height: SpacingTokens.sm),

            OutlinedButton.icon(
              onPressed: _testState == _TestState.loading ? null : _testConnection,
              icon: _testState == _TestState.loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_outlined),
              label: const Text('测试连接'),
            ),

            // 连接测试行内反馈
            if (_testState != _TestState.idle && _testMessage != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              Row(
                children: [
                  Icon(
                    _testState == _TestState.success
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _testState == _TestState.success
                        ? theme.semantic.success
                        : theme.semantic.caution,
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(
                    child: Text(
                      _testMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _testState == _TestState.success
                            ? theme.semantic.success
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (configured) ...[
              const SizedBox(height: SpacingTokens.xl),
              TextButton.icon(
                onPressed: _delete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  '删除配置',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
