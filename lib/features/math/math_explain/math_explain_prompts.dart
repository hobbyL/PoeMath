// lib/features/math/math_explain/math_explain_prompts.dart
//
// 层级：features/math/math_explain
// 职责：算数题 AI 解析的 Prompt 构造。纯 Dart。
//
// 隐私边界：userPrompt 只含题面、学生答案、正确答案与错因标签四项，
// 不含年级、题型、历史记录等任何其他用户数据（见 prd.md AC5）。
// 错因 category → 中文标签的单一来源在
// math_engine/diagnostics/error_cause_labels.dart（kErrorCauseLabels）。
//
// 默认 system prompt 常量迁至 core/prompts/explain_prompt_defaults.dart
// （设置页与 controller 共享的出厂默认）；此处 re-export 保持既有
// import 路径兼容。

export 'package:poemath/core/prompts/explain_prompt_defaults.dart';

/// 构造用户侧 Prompt。
///
/// [userAnswer] 为 null 表示孩子未作答（讲解模式）；
/// [errorCauseLabel] 为 null 表示无错因诊断。
String buildMathExplainUserPrompt({
  required String problemText,
  required String correctAnswer,
  String? userAnswer,
  String? errorCauseLabel,
}) {
  final buffer = StringBuffer()
    ..writeln('题目：$problemText')
    ..writeln('正确答案：$correctAnswer');
  if (userAnswer != null && userAnswer.trim().isNotEmpty) {
    buffer.writeln('孩子的答案：$userAnswer');
  }
  if (errorCauseLabel != null && errorCauseLabel.trim().isNotEmpty) {
    buffer.writeln('错误原因：$errorCauseLabel');
  }
  buffer.write('请按上面的要求讲解这道题。');
  return buffer.toString();
}
