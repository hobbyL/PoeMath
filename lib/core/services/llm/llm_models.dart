// lib/core/services/llm/llm_models.dart
//
// 层级：core/services/llm
// 职责：LLM 生成管线的轻量数据模型（草稿/批次结果）与错误分类。
//       纯 Dart，无 Hive/Flutter 依赖。


/// LLM 返回的单题草稿（尚未通过本地校验，内容不可信）。
class LlmWordProblemDraft {
  const LlmWordProblemDraft({
    required this.index,
    required this.text,
    required this.unit,
    required this.explanation,
  });

  /// 对应 skeleton 的序号（1-based）。
  final int index;

  /// 题面文本（LLM 输出）。
  final String text;

  /// 单位（LLM 输出，必须与 skeleton.unitHint 一致）。
  final String unit;

  /// 解题讲解（LLM 输出）。
  final String explanation;
}

/// 一次批量生成的结果：草稿按 index 与 skeleton 对齐（缺失即丢弃）。
class LlmBatchResult {
  const LlmBatchResult({required this.drafts});

  final List<LlmWordProblemDraft> drafts;
}

/// 自由文本讲解结果（诗词讲解 / 算数题解析共用）。
///
/// 内容为模型原样输出的纯文本（已 trim），不做结构解析：讲解类输出
/// 无需 JSON 校验，直接呈现给用户。
class LlmExplainResult {
  const LlmExplainResult({required this.text});

  /// 讲解正文。保证非空（空输出在客户端抛 [LlmResponseFormatError]）。
  final String text;
}

/// LLM 服务异常基类。所有子类 message 不得包含 apiKey。
sealed class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 网络不可达 / 超时。
class LlmNetworkError extends LlmException {
  const LlmNetworkError(super.message);
}

/// 鉴权失败（401 / 403）。
class LlmAuthError extends LlmException {
  const LlmAuthError(super.message);
}

/// 服务端错误（5xx）。
class LlmServerError extends LlmException {
  const LlmServerError(super.message);
}

/// 响应格式错误（JSON 解析失败、结构非法）。
class LlmResponseFormatError extends LlmException {
  const LlmResponseFormatError(super.message);
}

/// `GET /v1/models` 不可用（接口不支持 / 网络错误）。UI 退化手填。
class LlmModelsUnavailable extends LlmException {
  const LlmModelsUnavailable(super.message);
}
