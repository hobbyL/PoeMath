// lib/features/poem/poem_explain/poem_explain_models.dart
//
// 层级：features/poem/poem_explain
// 职责：诗词 AI 讲解的状态模型。纯 Dart，无 Flutter 依赖。
//
// 文本分段见 core/services/llm/llm_explain_text.dart（与口算侧共用）。

/// 讲解状态机。
enum PoemExplainStatus {
  /// 未请求过（卡片不展示正文）。
  idle,

  /// 请求中。
  loading,

  /// 讲解就绪。
  ready,

  /// 生成失败（含网络/鉴权/格式错误）。
  error,

  /// 未配置 LLM（引导去设置页）。
  unconfigured,
}

/// 诗词 AI 讲解状态。
class PoemExplainState {
  const PoemExplainState({
    this.status = PoemExplainStatus.idle,
    this.paragraphs = const <String>[],
    this.message,
    this.poemId,
  });

  final PoemExplainStatus status;

  /// 讲解段落（[PoemExplainStatus.ready] 时非空）。
  final List<String> paragraphs;

  /// 错误 / 引导文案。
  final String? message;

  /// 本次结果所属诗词 id（切诗时用于判定是否为当前诗词的结果）。
  final String? poemId;

  bool get isIdle => status == PoemExplainStatus.idle;
  bool get isLoading => status == PoemExplainStatus.loading;
  bool get isReady => status == PoemExplainStatus.ready;

  /// 朗读 / 分享用的完整文本。
  String get fullText => paragraphs.join('\n');
}
