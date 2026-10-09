// lib/features/math/math_explain/math_explain_prompts.dart
//
// 层级：features/math/math_explain
// 职责：算数题 AI 解析的 Prompt 构造与错因中文标签。纯 Dart。
//
// 隐私边界：userPrompt 只含题面、学生答案、正确答案与错因标签四项，
// 不含年级、题型、历史记录等任何其他用户数据（见 prd.md AC5）。

/// 错因 category → 中文标签（本地维护，不传诊断模板原文）。
///
/// key 对齐 math_engine 诊断器输出的 category。
const Map<String, String> kMathErrorCauseLabels = {
  'carry_omission': '进位遗漏',
  'borrow_omission': '退位遗漏',
  'multiplication_table': '口诀错误',
  'operation_order': '运算顺序错误',
  'remainder_mistake': '余数错误',
  'decimal_alignment': '小数对位错误',
};

/// 解析风格与铁律（固定常量）。
const String kMathExplainSystemPrompt = '''
你是一位给小学生讲口算题的数学老师。用普通话口语、短句讲解。

铁律（违反任何一条都算失败）：
1. 正确答案以我给出的为准，绝对不得改写、质疑或重新计算出别的答案；
2. 先一句话说清这道题怎么想，再分 2-3 步写清计算过程；
3. 如果我给了孩子的错误答案和错误原因，要点出错在哪一步、下次怎么避免；
4. 输出纯文本 3-5 小段，每段 1-2 句；
5. 不要使用 markdown 标题、加粗、列表符号、表情符号；
6. 不要出题、不要布置作业、不要说多余的鼓励套话。
''';

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
