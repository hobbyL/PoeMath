// lib/features/profile/llm_settings_page.dart
//
// 层级：features/profile
// 职责：应用题 AI 出题的 LLM 服务设置页（OpenAI 兼容）。
//       API Key 只进系统安全存储，页面不回显明文；留空保存 = 保留旧 Key。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

/// 页面内 LlmClient 的 http.Client 注入口：默认按 ProviderScope 缓存
/// 单个 client（onDispose 时关闭，复用连接池），测试覆写为 MockClient
/// 拦截网络层。LlmClient 注入后不持有所有权，close() 不会关闭它。
final llmSettingsHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// 连接测试的行内反馈状态。
enum _TestState { idle, loading, success, failure }

class LlmSettingsPage extends ConsumerStatefulWidget {
  const LlmSettingsPage({super.key});

  @override
  ConsumerState<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends ConsumerState<LlmSettingsPage> {
  final _providerNameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// 是否已存 API Key（决定占位提示文案；不回显明文）。
  bool _hasStoredKey = false;

  /// 模型拉取状态（防重入 + suffixIcon 加载态）。
  bool _fetchingModels = false;

  _TestState _testState = _TestState.idle;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final settingsRepo = ref.read(settingsRepositoryProvider);
    _providerNameController.text = settingsRepo.llmProviderName;
    _baseUrlController.text = settingsRepo.llmBaseUrl;
    _modelController.text = settingsRepo.llmModel;
    _loadStoredKey();
  }

  @override
  void dispose() {
    _providerNameController.dispose();
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

  /// 用当前表单值构造配置。modelEmpty 时放宽为仅校验服务地址
  /// （模型拉取场景不依赖 model）。
  LlmConfig? _buildConfigFromForm({bool modelEmpty = false}) {
    final base = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (base.isEmpty) return null;
    if (!modelEmpty && model.isEmpty) return null;
    return LlmConfig(
      baseUrl: base,
      apiKey: _apiKeyController.text.trim(),
      model: model,
    );
  }

  /// 点击拉取按钮：用表单 url/key（Key 空时回退已存 Key）请求模型列表，
  /// 成功弹底部列表供选择，失败提示继续手填。
  Future<void> _fetchModels() async {
    if (_fetchingModels) return;
    final config = _buildConfigFromForm(modelEmpty: true);
    if (config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写服务地址')),
      );
      return;
    }
    // 加载态先于任何 await：回退已存 Key 要读安全存储（平台通道在低端
    // 设备上有可感知耗时），读取期间按钮同样不可再点——防重入覆盖
    // 整个拉取周期，而不是仅网络请求阶段。
    setState(() => _fetchingModels = true);
    final client = LlmClient(
      httpClient: ref.read(llmSettingsHttpClientProvider),
    );
    List<String> models;
    try {
      var configToFetch = config;
      if (_apiKeyController.text.trim().isEmpty && _hasStoredKey) {
        final stored =
            await ref.read(secureCredentialStoreProvider).readLlmApiKey();
        configToFetch = LlmConfig(
          baseUrl: config.baseUrl,
          apiKey: stored ?? '',
          model: config.model,
        );
      }
      models = await client.listModels(configToFetch);
    } on LlmException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取模型失败：${e.message}，可手动填写')),
        );
      }
      return;
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('服务地址无效：${e.message}')),
        );
      }
      return;
    } finally {
      client.close();
      // 网络阶段结束（含失败）即停加载态：按钮区不能停留在
      // 无限转圈的 CircularProgressIndicator 上（弹层选择期间与测试
      // pumpAndSettle 都要求无持续动画）。
      if (mounted) setState(() => _fetchingModels = false);
    }
    if (!mounted) return;
    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务未返回模型，请手动填写')),
      );
      return;
    }
    final selected = await _pickModelSheet(models);
    if (selected != null && mounted) {
      setState(() => _modelController.text = selected);
    }
  }

  /// 底部弹层模型列表；返回选中模型名，取消返回 null。
  Future<String?> _pickModelSheet(List<String> models) {
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
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(
                      bottom: SpacingTokens.md,
                    ),
                    children: [
                      for (final model in models)
                        ListTile(
                          title: Text(model),
                          selected:
                              model == _modelController.text.trim(),
                          selectedColor: theme.colorScheme.primary,
                          onTap: () => Navigator.pop(sheetContext, model),
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
    final client = LlmClient(
      httpClient: ref.read(llmSettingsHttpClientProvider),
    );
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
        providerName: _providerNameController.text.trim(),
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
        content: const Text('将删除供应商名称、服务地址、模型名与已保存的 API Key，'
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
      _providerNameController.clear();
      _baseUrlController.clear();
      _modelController.clear();
      _apiKeyController.clear();
      _hasStoredKey = false;
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
              controller: _providerNameController,
              decoration: const InputDecoration(
                labelText: '供应商名称（可选）',
                hintText: '例如 DeepSeek、通义千问',
                prefixIcon: Icon(Icons.business_outlined),
                border: OutlineInputBorder(),
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
            const SizedBox(height: SpacingTokens.md),

            TextFormField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: '模型',
                hintText: '可手动填写，或点击右侧按钮拉取',
                prefixIcon: const Icon(Icons.model_training_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: _fetchingModels
                    ? const Padding(
                        padding:
                            EdgeInsets.all(SpacingTokens.sm + SpacingTokens.xs),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: '从服务拉取模型列表',
                        onPressed: _fetchModels,
                      ),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return '请填写模型名';
                return null;
              },
            ),
            const SizedBox(height: SpacingTokens.lg),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testState == _TestState.loading
                        ? null
                        : _testConnection,
                    icon: _testState == _TestState.loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_outlined),
                    label: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存配置'),
                  ),
                ),
              ],
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
