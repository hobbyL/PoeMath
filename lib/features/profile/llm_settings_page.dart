// lib/features/profile/llm_settings_page.dart
//
// 层级：features/profile
// 职责：应用题 AI 出题的 LLM 服务设置页（OpenAI 兼容，多厂商配置）。
//       页面上半部为「我的配置」列表（点行切换生效），下半部为编辑区
//       （新增 / 编辑当前选中条目）。API Key 只进系统安全存储，
//       页面不回显明文；编辑已有配置时 Key 留空 = 保留该配置旧 Key。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
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

  /// 正在编辑的配置 id；null = 新增表单。
  String? _editingId;

  /// 当前编辑配置是否已存 API Key（决定占位提示文案；不回显明文）。
  bool _hasStoredKey = false;

  /// 正在读取编辑配置的已存 Key（_startEdit 防重入）。
  bool _loadingStoredKey = false;

  /// 保存中（_save 防重入）。
  bool _saving = false;

  /// 模型拉取状态（防重入 + suffixIcon 加载态）。
  bool _fetchingModels = false;

  _TestState _testState = _TestState.idle;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    // 迁移与初始装载走异步：initState 内不得 await（FakeAsync 下 Hive
    // 写链会挂起，且 setState-in-initState 会触发框架断言），参照
    // speech_recognition_settings_page 的 unawaited 先例。
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _providerNameController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 迁移旧单配置 → 载入列表；有配置时默认编辑生效配置，
  /// 无配置为新增空表单。
  Future<void> _bootstrap() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    try {
      await settingsRepo.migrateLegacyLlmConfigIfNeeded();
      final providers = settingsRepo.llmProviders;
      if (providers.isNotEmpty) {
        // 默认编辑生效配置（新用户首选项）。
        final activeId = settingsRepo.llmActiveProviderId;
        final target = providers.where((p) => p.id == activeId).firstOrNull;
        await _startEdit(target ?? providers.first);
      }
    } on Object catch (error) {
      AppLogger.e('LLM 设置页初始化失败', tag: 'LlmSettings', error: error);
    }
  }

  /// 载入指定配置到编辑区（点编辑按钮 / 初始化默认编辑）。
  Future<void> _startEdit(LlmProviderConfig config) async {
    // 防重入守卫先于任何 await（含安全存储读取）：读取期间二次点击
    // 不得发起重复读取（state-management.md「Loading Guard Must
    // Precede the First await」）。
    if (_loadingStoredKey) return;
    setState(() => _loadingStoredKey = true);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    try {
      final stored = await settingsRepo.readLlmApiKeyFor(config.id);
      if (!mounted) return;
      setState(() {
        _editingId = config.id;
        _providerNameController.text = config.name;
        _baseUrlController.text = config.baseUrl;
        _modelController.text = config.model;
        _apiKeyController.clear();
        _hasStoredKey = stored != null && stored.trim().isNotEmpty;
        _testState = _TestState.idle;
        _testMessage = null;
      });
    } finally {
      if (mounted) setState(() => _loadingStoredKey = false);
    }
  }

  /// 「新增配置」：编辑区重置为空表单（编辑对象与生效选择互相独立，
  /// 不触碰 active）。
  void _startCreate() {
    setState(() {
      _editingId = null;
      _providerNameController.clear();
      _baseUrlController.clear();
      _modelController.clear();
      _apiKeyController.clear();
      _hasStoredKey = false;
      _testState = _TestState.idle;
      _testMessage = null;
    });
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

  /// Key 留空时回退当前编辑配置的已存 Key（仅编辑已存配置时）。
  Future<String?> _fallbackStoredKey() async {
    final editingId = _editingId;
    if (editingId == null) return null;
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readLlmApiKeyFor(editingId);
    if (stored == null || stored.trim().isEmpty) return null;
    return stored;
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
        final stored = await _fallbackStoredKey();
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
    if (_testState == _TestState.loading) return;
    final config = _buildConfigFromForm();
    if (config == null) {
      setState(() {
        _testState = _TestState.failure;
        _testMessage = '请先填写服务地址和模型名';
      });
      return;
    }
    // 加载态先于任何 await：回退已存 Key 要读安全存储（平台通道在
    // 低端设备上有可感知耗时），读取期间按钮同样不可再点。
    setState(() {
      _testState = _TestState.loading;
      _testMessage = null;
    });
    var configToTest = config;
    if (_apiKeyController.text.trim().isEmpty && _hasStoredKey) {
      final stored = await _fallbackStoredKey();
      configToTest = LlmConfig(
        baseUrl: config.baseUrl,
        apiKey: stored ?? '',
        model: config.model,
      );
    }
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

    // 防重入守卫先于任何 await（Key 回退读取要过平台通道）。
    if (_saving) return;
    setState(() => _saving = true);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final id = _editingId ?? LlmProviderConfig.generateId();
    try {
      // 留空保存 = 保留旧 Key：仓储侧 apiKey 空串即保留语义，
      // 页面无须读回明文。
      await settingsRepo.saveLlmProviderConfig(
        id: id,
        name: _providerNameController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        model: _modelController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      );
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('服务地址无效：${e.message}')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;
    setState(() {
      // 新增后切到新 id，便于直接继续编辑/删除。
      _editingId = id;
      _apiKeyController.clear();
    });
    await _refreshStoredKeyFlag(id);
    if (!mounted) return;
    ref.invalidate(settingsRepositoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('LLM 服务配置已保存')),
    );
  }

  /// 保存后重读当前编辑配置的已存 Key 标志（不回显明文）。
  Future<void> _refreshStoredKeyFlag(String id) async {
    final stored =
        await ref.read(settingsRepositoryProvider).readLlmApiKeyFor(id);
    if (mounted) {
      setState(() => _hasStoredKey = stored != null && stored.trim().isNotEmpty);
    }
  }

  Future<void> _delete() {
    return _deleteEditing();
  }

  /// 删除当前编辑的配置（确认弹窗）；删的是 _editingId 则表单重置新增态。
  Future<void> _deleteEditing() async {
    final editingId = _editingId;
    if (editingId == null) return;
    final name = _providerNameController.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除此配置'),
        content: Text(
          '将删除「${name.isEmpty ? '未命名配置' : name}」的服务地址、模型名与'
          '已保存的 API Key。删除的是生效配置时，生效自动切换到剩余'
          '第一条。题库中已有的题目不受影响。',
        ),
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

    await ref.read(settingsRepositoryProvider).deleteLlmProviderConfig(
          editingId,
        );
    if (!mounted) return;
    setState(() {
      _editingId = null;
      _providerNameController.clear();
      _baseUrlController.clear();
      _modelController.clear();
      _apiKeyController.clear();
      _hasStoredKey = false;
      _testState = _TestState.idle;
      _testMessage = null;
    });
    ref.invalidate(settingsRepositoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('LLM 服务配置已删除')),
    );
  }

  /// 列表行显示名：空名兜底「配置 N」（N 为序号，不回写存储）。
  String _displayName(int index, LlmProviderConfig config) {
    final name = config.name.trim();
    if (name.isNotEmpty) return name;
    return '配置 ${index + 1}';
  }

  /// baseUrl 宿主名摘要（列表副标题；解析失败回退原串）。
  String _hostSummary(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    final host = uri?.host ?? '';
    if (host.isNotEmpty) return host;
    return baseUrl;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsRepo = ref.watch(settingsRepositoryProvider);
    final providers = settingsRepo.llmProviders;
    final activeId = settingsRepo.llmActiveProviderId;
    final editing =
        providers.where((p) => p.id == _editingId).firstOrNull;

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
                  '还没有 LLM 配置。在下方填写供应商信息并点击「保存配置」，'
                  '即可添加第一个配置；也可以同时保存多个厂商配置，'
                  '在列表中点选切换生效。',
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
                  borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
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
                            title: Text(_displayName(index, config)),
                            subtitle: Text(_hostSummary(config.baseUrl)),
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: '编辑此配置',
                              onPressed: () => _startEdit(config),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: SpacingTokens.sm),
            OutlinedButton.icon(
              onPressed: _startCreate,
              icon: const Icon(Icons.add_outlined),
              label: const Text('新增配置'),
            ),
            const SizedBox(height: SpacingTokens.lg),

            // ============ 编辑区 ============
            Text(
              editing != null
                  ? '编辑：${_displayName(providers.indexOf(editing), editing)}'
                  : '新增配置',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
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
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
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

            if (editing != null) ...[
              const SizedBox(height: SpacingTokens.xl),
              TextButton.icon(
                onPressed: _delete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  '删除此配置',
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
