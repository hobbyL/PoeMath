// lib/features/profile/widgets/llm_provider_edit_dialog.dart
//
// 层级：features/profile/widgets
// 职责：供应商配置「新增 / 编辑」全屏弹窗 —— 由供应商设置页列表的
//       「新增配置」与每行编辑按钮唤起（替代原页面底部内联表单）。
//       承载表单字段、模型拉取、连接测试、保存、清除 Key 与删除。
//
// API Key 纪律（与仓储一致）：只进系统安全存储，不写 Hive / 日志 / 异常
// message。编辑时回显已存 Key（默认密文，点输入框右侧「眼睛」切换明文）便于
// 家长核对；字段清空后保存 = 保留旧 Key（仓储语义），彻底移除走「清除已保存
// 的 Key」。readLlmApiKeyFor 用于回显、「是否已存」标志与测试/拉取时的回退。
//
// 反馈分流：弹窗内提示（校验/拉取/测试/清除）走弹窗局部
// ScaffoldMessenger（否则 SnackBar 落在被全屏弹窗遮挡的底层页）；
// 保存/删除成功以 [LlmProviderEditResult] 回传，由列表页在应用级
// Messenger 弹确认（弹窗已 pop，局部 Messenger 随之消失）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';

/// 弹窗内 LlmClient 的 http.Client 注入口：默认按 ProviderScope 缓存
/// 单个 client（onDispose 时关闭，复用连接池），测试覆写为 MockClient
/// 拦截网络层。LlmClient 注入后不持有所有权，close() 不会关闭它。
final llmSettingsHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// 连接测试的行内反馈状态。
enum _TestState { idle, loading, success, failure }

/// 弹窗关闭回传：区分保存与删除，供列表页弹对应确认 SnackBar。
enum LlmProviderEditResult { saved, deleted }

/// 打开全屏「新增 / 编辑供应商配置」弹窗。
///
/// [config] 为 null = 新增；非 null = 编辑该配置（弹窗生命周期内 id 固定）。
/// 返回 [LlmProviderEditResult] 表示发生了保存 / 删除（列表页据此刷新并
/// 弹确认）；返回 null = 用户取消（无副作用）。
Future<LlmProviderEditResult?> showLlmProviderEditDialog(
  BuildContext context, {
  LlmProviderConfig? config,
}) {
  return showDialog<LlmProviderEditResult>(
    context: context,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      child: _LlmProviderEditDialog(config: config),
    ),
  );
}

class _LlmProviderEditDialog extends ConsumerStatefulWidget {
  const _LlmProviderEditDialog({this.config});

  final LlmProviderConfig? config;

  @override
  ConsumerState<_LlmProviderEditDialog> createState() =>
      _LlmProviderEditDialogState();
}

class _LlmProviderEditDialogState
    extends ConsumerState<_LlmProviderEditDialog> {
  final _providerNameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// 候选模型清单（含默认模型）。配置时可拉取多选 / 手动增删；用时各场景从中选。
  final List<String> _models = <String>[];

  /// 弹窗局部 Messenger：拉取/测试/清除/校验提示在此弹，避免落到被全屏
  /// 弹窗遮挡的底层页；保存/删除成功的确认由列表页在应用级 Messenger 弹。
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 正在编辑的配置 id；null = 新增。弹窗生命周期内固定（不随保存变化），
  /// 故无需原页面的 _editSeq 竞态令牌。
  String? get _editingId => widget.config?.id;

  /// 编辑态是否已存在 Key（决定「清除已保存的 Key」入口与 Key 空回退）。
  bool _hasStoredKey = false;

  /// API Key 输入框明/密文切换（默认密文，点眼睛查看）。
  bool _apiKeyVisible = false;
  bool _saving = false;
  bool _fetchingModels = false;
  _TestState _testState = _TestState.idle;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    if (config != null) {
      _providerNameController.text = config.name;
      _baseUrlController.text = config.baseUrl;
      _modelController.text = config.model;
      _models.addAll(config.models);
      unawaited(_loadStoredKey(config.id));
    }
  }

  /// 把模型名加入候选清单（去空白、去重）。
  void _addModel(String model) {
    final m = model.trim();
    if (m.isEmpty || _models.contains(m)) return;
    setState(() => _models.add(m));
  }

  @override
  void dispose() {
    _providerNameController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 编辑态读取已存 Key：回显到输入框（默认密文）并置「已存」标志
  /// （后者决定清除入口与 Key 空回退）。
  Future<void> _loadStoredKey(String id) async {
    final stored =
        await ref.read(settingsRepositoryProvider).readLlmApiKeyFor(id);
    if (!mounted) return;
    final hasKey = stored != null && stored.trim().isNotEmpty;
    setState(() {
      _hasStoredKey = hasKey;
      if (hasKey) _apiKeyController.text = stored;
    });
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

  /// 点击拉取按钮：用表单 url/key（Key 空回退已存 Key）请求模型列表，
  /// 成功弹底部列表供选择，失败提示继续手填。
  Future<void> _fetchModels() async {
    if (_fetchingModels) return;
    final config = _buildConfigFromForm(modelEmpty: true);
    if (config == null) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('请先填写服务地址')),
      );
      return;
    }
    // 加载态先于任何 await：回退已存 Key 要读安全存储，读取期间按钮
    // 同样不可再点（防重入覆盖整个拉取周期，而不仅网络请求阶段）。
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
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('拉取模型失败：${e.message}，可手动填写')),
        );
      }
      return;
    } on FormatException catch (e) {
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('服务地址无效：${e.message}')),
        );
      }
      return;
    } finally {
      client.close();
      if (mounted) setState(() => _fetchingModels = false);
    }
    if (!mounted) return;
    if (models.isEmpty) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('服务未返回模型，请手动填写')),
      );
      return;
    }
    final selected = await _pickModelsSheet(models);
    if (selected != null && selected.isNotEmpty && mounted) {
      setState(() {
        for (final m in selected) {
          if (!_models.contains(m)) _models.add(m);
        }
        // 默认模型为空时取第一个选中的，保证有默认可用。
        if (_modelController.text.trim().isEmpty) {
          _modelController.text = selected.first;
        }
      });
    }
  }

  /// 底部弹层：多选模型，返回勾选的模型名列表；取消返回 null。
  /// 已在候选清单中的模型默认勾选，便于增量加入。
  Future<List<String>?> _pickModelsSheet(List<String> models) {
    final chosen = <String>{..._models.where(models.contains)};
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      child: Text(
                        '选择模型（可多选）',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final model in models)
                            CheckboxListTile(
                              value: chosen.contains(model),
                              title: Text(model),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              onChanged: (v) => setSheetState(() {
                                if (v ?? false) {
                                  chosen.add(model);
                                } else {
                                  chosen.remove(model);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, chosen.toList()),
                          child: Text('加入 ${chosen.length} 个模型'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 测试连接：用表单 url/model/key（Key 空回退已存 Key）发一次最小请求，
  /// 结果以行内反馈（_testState/_testMessage）呈现，不弹 SnackBar。
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
    // 加载态先于任何 await：回退已存 Key 要读安全存储，读取期间按钮不可再点。
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

  /// 保存配置：校验 → 写入（留空 Key = 保留旧 Key，仓储侧语义，页面无须
  /// 读回明文）→ 成功回传 [LlmProviderEditResult.saved] 并关闭弹窗
  /// （列表页据此刷新并在应用级 Messenger 弹确认）。
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // 防重入守卫先于任何 await（Key 回退读取要过平台通道）。
    if (_saving) return;
    setState(() => _saving = true);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final navigator = Navigator.of(context);
    final id = _editingId ?? LlmProviderConfig.generateId();
    try {
      await settingsRepo.saveLlmProviderConfig(
        id: id,
        name: _providerNameController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        model: _modelController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        models: _models,
      );
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('服务地址无效：${e.message}')),
        );
      }
      return;
    }
    if (!mounted) return;
    navigator.pop(LlmProviderEditResult.saved);
  }

  /// 清除当前编辑配置已保存的 API Key（如从有鉴权服务切到无鉴权服务）：
  /// 确认弹层 → repo.clearLlmApiKey → _hasStoredKey=false，输入框一并清空、
  /// 占位提示回退到「无鉴权服务可留空」。服务地址与模型保留；「留空 = 保留
  /// 旧 Key」语义不变（清除后无已存 Key，留空即不带 Key）。
  Future<void> _clearStoredKey() async {
    final editingId = _editingId;
    if (editingId == null || !_hasStoredKey) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除已保存的 Key'),
        content: const Text(
          '清除后该配置将不带 Key 请求（适合无鉴权服务）；配置的服务地址'
          '与模型保留。可随时重新填写 Key 并保存恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(settingsRepositoryProvider).clearLlmApiKey(editingId);
    if (!mounted) return;
    setState(() {
      _hasStoredKey = false;
      // 回显的 Key 一并抹掉，避免清除后输入框仍留明文旧值。
      _apiKeyController.clear();
      _apiKeyVisible = false;
    });
    _messengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('已清除保存的 API Key')),
    );
  }

  /// 删除当前编辑的配置（确认弹窗）→ 成功回传
  /// [LlmProviderEditResult.deleted] 并关闭弹窗。删的是生效配置时，
  /// 仓储侧自动把生效切到剩余第一条。
  Future<void> _deleteEditing() async {
    final editingId = _editingId;
    if (editingId == null) return;
    final name = _providerNameController.text.trim();
    final navigator = Navigator.of(context);
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
    await ref
        .read(settingsRepositoryProvider)
        .deleteLlmProviderConfig(editingId);
    if (!mounted) return;
    navigator.pop(LlmProviderEditResult.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = widget.config;
    final isEditing = _editingId != null;
    final title = config == null
        ? '新增配置'
        : (config.name.trim().isEmpty
            ? '编辑配置'
            : '编辑：${config.name.trim()}');

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(title),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
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
                obscureText: !_apiKeyVisible,
                decoration: InputDecoration(
                  labelText: 'API Key（可选）',
                  hintText: '无鉴权服务可留空',
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: const OutlineInputBorder(),
                  // 输入框右侧「眼睛」：切换明/密文查看（默认密文）。
                  suffixIcon: IconButton(
                    icon: Icon(
                      _apiKeyVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    tooltip: _apiKeyVisible ? '隐藏 API Key' : '显示 API Key',
                    onPressed: () =>
                        setState(() => _apiKeyVisible = !_apiKeyVisible),
                  ),
                ),
              ),
              // 清除已存 Key 入口：仅编辑已存 Key 的配置时出现。
              if (isEditing && _hasStoredKey)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _clearStoredKey,
                    icon: const Icon(Icons.key_off_outlined),
                    label: const Text('清除已保存的 Key'),
                  ),
                ),
              const SizedBox(height: SpacingTokens.md),

              TextFormField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: '默认模型',
                  hintText: '手动填写或点右侧拉取；留空取候选第一个',
                  prefixIcon: const Icon(Icons.model_training_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: _fetchingModels
                      ? const Padding(
                          padding: EdgeInsets.all(
                            SpacingTokens.sm + SpacingTokens.xs,
                          ),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: '从服务拉取模型列表（可多选）',
                          onPressed: _fetchModels,
                        ),
                ),
                onChanged: (_) => setState(() {}),
                // 默认模型会在保存时并入候选清单；手动输入也可直接作为默认。
                onFieldSubmitted: _addModel,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return '请填写默认模型';
                  return null;
                },
              ),
              // 候选模型清单（配置时可多选；用时各功能里从中切换）。
              if (_models.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '候选模型（用时可在各功能里切换；点 × 移除）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.xs,
                  children: <Widget>[
                    for (final m in _models)
                      InputChip(
                        label: Text(m),
                        onDeleted: () => setState(() {
                          _models.remove(m);
                          if (_modelController.text.trim() == m) {
                            _modelController.text =
                                _models.isNotEmpty ? _models.first : '';
                          }
                        }),
                      ),
                  ],
                ),
              ],
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

              // 删除入口：仅编辑已有配置时出现（新增态无删除对象）。
              if (isEditing) ...[
                const SizedBox(height: SpacingTokens.xl),
                TextButton.icon(
                  onPressed: _deleteEditing,
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
      ),
    );
  }
}
