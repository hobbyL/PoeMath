// lib/features/math/math_explain/math_explain_models.dart
//
// 层级：features/math/math_explain
// 职责：算数题 AI 解析的状态模型。纯 Dart，无 Flutter 依赖。
//
// 分段工具见 core/services/llm/llm_explain_text.dart（与诗词侧共用）。

/// 解析状态机（与诗词侧同构）。
enum MathExplainStatus { idle, loading, ready, error, unconfigured }

/// 算数题 AI 解析状态。
class MathExplainState {
  const MathExplainState({
    this.status = MathExplainStatus.idle,
    this.paragraphs = const <String>[],
    this.message,
    this.problemText,
  });

  final MathExplainStatus status;

  /// 解析段落（[MathExplainStatus.ready] 时非空）。
  final List<String> paragraphs;

  /// 错误 / 引导文案。
  final String? message;

  /// 本次结果所属题面（换题时用于判定是否为当前题目的结果）。
  final String? problemText;

  bool get isIdle => status == MathExplainStatus.idle;
  bool get isLoading => status == MathExplainStatus.loading;
  bool get isReady => status == MathExplainStatus.ready;
}
