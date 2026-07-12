// lib/math_engine/models/answer_judgement.dart
//
// 判定结果与错因诊断模型。

/// 错因诊断。
class MistakeDiagnosis {
  /// 错因类别标识。
  final String category;

  /// 自然语言讲解模板。
  final String template;

  /// 模板参数。
  final Map<String, String> params;

  const MistakeDiagnosis({
    required this.category,
    required this.template,
    this.params = const {},
  });

  /// 渲染后的讲解文本。
  String get message {
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  @override
  String toString() => '$category: $message';
}

/// 分步解题步骤。
class SolutionStep {
  /// 步骤描述（面向小学生的自然语言）。
  final String description;

  /// 算式表达式。
  final String expression;

  /// 结果提示。
  final String resultHint;

  const SolutionStep({
    required this.description,
    required this.expression,
    this.resultHint = '',
  });

  @override
  String toString() => '$description: $expression → $resultHint';
}

/// 答案判定结果。
class AnswerJudgement {
  /// 是否正确。
  final bool isCorrect;

  /// 错因诊断（仅错误时有值）。
  final MistakeDiagnosis? diagnosis;

  /// 正确的分步解答。
  final List<SolutionStep> correctSteps;

  const AnswerJudgement({
    required this.isCorrect,
    this.diagnosis,
    this.correctSteps = const [],
  });

  @override
  String toString() => isCorrect ? '✓ 正确' : '✗ 错误 ($diagnosis)';
}
