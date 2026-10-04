// lib/features/math/word_problem/word_problem_validator.dart
//
// 应用题草稿四重校验器（design §3.3）：LLM 输出不可信，入库前必须通过：
// 1) 数字一致性（多重集合与 operands 完全相等，题面不得出现答案）
// 2) 语义一致（运算用词与运算类型不冲突）
// 3) 数学正确（ExpressionEvaluator 复算 == 答案）
// 4) 形态约束（长度、无运算符号、单位一致）
// 返回 null = 通过；返回 String = 违规原因（供家长预览页提示）。

import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/validators/expression_evaluator.dart';

// ============ 词表常量 ============

/// 与加法语义冲突的词（减法情境用语）。
const List<String> kSubtractionConflictWords = [
  '还剩',
  '找回',
  '少了',
  '用去',
  '花了',
];

/// 与减法语义冲突的词（加法/合并情境用语）。
const List<String> kAdditionConflictWords = ['一共', '总共'];

/// 题面中禁止出现的符号（LLM 不得把算式写进题面）。
final RegExp kForbiddenSymbolPattern =
    RegExp(r'[+−×÷=()＋－＊／（）]');

/// 非整数数字（应用题骨架全为整数，出现小数即违规）。
final RegExp _decimalPattern = RegExp(r'\d+\.\d+');

/// 应用题草稿校验器。
class WordProblemValidator {
  const WordProblemValidator._();

  /// 校验单题草稿。返回 null = 通过；返回 String = 违规原因。
  ///
  /// [draft] 为 LLM 输出（不可信），[skeleton] 为本地既定结构（可信）。
  static String? validate({
    required LlmWordProblemDraft draft,
    required ProblemSkeleton skeleton,
  }) {
    final text = draft.text;
    final explanation = draft.explanation;

    // ---- 4) 形态约束（先做，成本最低且独立于数学内容） ----
    if (text.trim().isEmpty) return '题面为空';
    if (text.length > 120) return '题面超过 120 字';
    final forbidden = kForbiddenSymbolPattern.firstMatch(text);
    if (forbidden != null) return '题面包含运算符号或算式：${forbidden.group(0)}';
    if (draft.unit != skeleton.unitHint) {
      return '单位与骨架不一致：应为「${skeleton.unitHint}」，实际「${draft.unit}」';
    }

    // ---- 1) 数字一致性 ----
    // 骨架全为整数：题面出现小数（如「12.5」）直接拒绝，
    // 防止 ×10 恰好撞上合法操作数造成误放行。
    if (_decimalPattern.hasMatch(text)) {
      return '题面包含非整数数字';
    }
    final textNumbers = _extractNumbers(text);
    final expectedNumbers = List<int>.from(skeleton.operands);
    // 答案泄露：答案不等于任何操作数时，题面不得出现答案。
    // （若答案恰为某操作数，如 3 × 1 = 3，题面必然含该数字，不误报。）
    final answerIsOperand =
        skeleton.operands.contains(skeleton.answer);
    if (!answerIsOperand && textNumbers.contains(skeleton.answer)) {
      return '题面中出现了答案 ${skeleton.answer}';
    }
    if (!_multisetEquals(textNumbers, expectedNumbers)) {
      return '题面数字与骨架不一致：应为 ${expectedNumbers.join('、')}，'
          '实际为 ${textNumbers.isEmpty ? '（无数字）' : textNumbers.join('、')}';
    }

    // ---- 2) 语义一致 ----
    final semanticError = _checkSemantics(text, skeleton.operators);
    if (semanticError != null) return semanticError;

    // ---- 3) 数学正确（骨架权威复算，防御骨架被篡改） ----
    final operands = skeleton.operands
        .map(NumberValue.fromInt)
        .toList();
    final evaluated = ExpressionEvaluator.evaluate(operands, skeleton.operators);
    if (evaluated == null || !evaluated.isInteger) {
      return '骨架算式无法求出整数结果';
    }
    if (evaluated.asInteger != skeleton.answer) {
      return '骨架算式求值与答案不一致';
    }

    // ---- explanation 数字检查 ----
    if (explanation.trim().isNotEmpty) {
      if (_decimalPattern.hasMatch(explanation)) {
        return '讲解包含非整数数字';
      }
      final explanationNumbers = _extractNumbers(explanation);
      final allowed = List<int>.from(skeleton.operands)
        ..add(skeleton.answer);
      for (final n in explanationNumbers) {
        if (!allowed.contains(n)) {
          return '讲解引入了新数字 $n（只能引用题目数字与答案）';
        }
      }
    }

    return null;
  }

  /// 提取文本中的全部整数数字串（多位整数）。
  /// 小数已由 [_decimalPattern] 在调用前拒绝，此处只处理纯整数。
  static List<int> _extractNumbers(String text) {
    final matches = RegExp(r'\d+').allMatches(text);
    final numbers = <int>[];
    for (final match in matches) {
      final value = int.tryParse(match.group(0)!);
      if (value != null) numbers.add(value);
    }
    return numbers;
  }

  /// 语义一致性：
  /// - 含加/乘 → 禁减法情境词（还剩/找回/少了/用去/花了）；
  /// - 含减 → 禁加法情境词（一共/总共）；
  /// - 含除 → 禁加法情境词（一共/总共）。
  static String? _checkSemantics(
    String text,
    List<Operator> operators,
  ) {
    final hasAdd = operators.contains(Operator.add);
    final hasSub = operators.contains(Operator.subtract);
    final hasMul = operators.contains(Operator.multiply);
    final hasDiv = operators.contains(Operator.divide);

    if (hasAdd || hasMul) {
      for (final word in kSubtractionConflictWords) {
        if (text.contains(word)) {
          return '加/乘法题面出现了减法情境词「$word」';
        }
      }
    }
    if (hasSub) {
      for (final word in kAdditionConflictWords) {
        if (text.contains(word)) {
          return '减法题面出现了加法情境词「$word」';
        }
      }
    }
    if (hasDiv) {
      for (final word in kAdditionConflictWords) {
        if (text.contains(word)) {
          return '除法题面出现了加法情境词「$word」';
        }
      }
    }
    return null;
  }

  /// 多重集合相等（含重复次数）。
  static bool _multisetEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final counts = <int, int>{};
    for (final v in a) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    for (final v in b) {
      final count = counts[v] ?? 0;
      if (count == 0) return false;
      counts[v] = count - 1;
    }
    return true;
  }
}

