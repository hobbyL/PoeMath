// lib/core/services/llm/llm_config.dart
//
// 层级：core/services/llm
// 职责：OpenAI 兼容 LLM 服务配置。
//       apiKey 仅运行时注入，不参与任何序列化；toString 不泄露 apiKey。

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
  });

  /// 服务地址（用户原样输入，请求时经 [LlmClient.normalizeBaseUrl] 规范化）。
  final String baseUrl;

  /// API Key。允许为空（Ollama 等无鉴权服务）。
  final String apiKey;

  /// 模型名。
  final String model;

  /// 是否配置了非空 API Key。
  bool get hasApiKey => apiKey.trim().isNotEmpty;

  @override
  String toString() =>
      'LlmConfig(baseUrl: $baseUrl, model: $model, '
      'apiKey: ${hasApiKey ? '<已设置，不回显>' : '<未设置>'})';
}
