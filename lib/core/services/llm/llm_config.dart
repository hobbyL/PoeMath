// lib/core/services/llm/llm_config.dart
//
// 层级：core/services/llm
// 职责：OpenAI 兼容 LLM 服务配置。
//       apiKey 仅运行时注入，不参与任何序列化；toString 不泄露 apiKey。

import 'package:poemath/core/services/llm/llm_scenario.dart';

/// 请求开始时的非敏感选择快照，仅用于自动切换成功后的条件回写。
class LlmSelectionSnapshot {
  LlmSelectionSnapshot({
    required this.providerId,
    required this.scenario,
    required this.defaultModel,
    required List<String> models,
    required this.boundProviderId,
    required this.selectedModel,
    this.providerVersion = 0,
  }) : models = List.unmodifiable(models);

  final String providerId;
  final LlmScenario scenario;
  final String defaultModel;
  final List<String> models;
  final String? boundProviderId;
  final String? selectedModel;
  final int providerVersion;
}

/// LLM 服务配置（OpenAI 兼容）。
///
/// 安全边界：[apiKey] 只允许出现在 `Authorization: Bearer` 请求头与
/// flutter_secure_storage；不得写入 Hive、日志、异常 message 或 toString。
/// 刻意不覆写 `==`/`hashCode`（避免在断言或日志中间接暴露 Key 内容）。
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.models = const [],
    this.selection,
    this.fallbacks = const [],
  });

  /// 服务地址（用户原样输入，请求时经 [LlmClient.normalizeBaseUrl] 规范化）。
  final String baseUrl;

  /// API Key。允许为空（Ollama 等无鉴权服务）。
  final String apiKey;

  /// 模型名。
  final String model;

  /// 同一服务商已选候选；旧三字段配置仍只调用 [model]。
  final List<String> models;
  final LlmSelectionSnapshot? selection;

  /// 其余已配置供应商，按设置列表排序；只存在内存，不参与序列化。
  final List<LlmConfig> fallbacks;

  List<String> get candidateModels => <String>{
        model.trim(),
        for (final candidate in models) candidate.trim(),
      }.where((candidate) => candidate.isNotEmpty).toList();

  /// 只替换请求模型，保留原始选择快照供成功回写校验。
  LlmConfig withModel(String value) => LlmConfig(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: value,
        models: models,
        selection: selection,
        fallbacks: fallbacks,
      );

  /// 是否配置了非空 API Key。
  bool get hasApiKey => apiKey.trim().isNotEmpty;

  @override
  String toString() => 'LlmConfig(baseUrl: $baseUrl, model: $model, '
      'apiKey: ${hasApiKey ? '<已设置，不回显>' : '<未设置>'})';
}
