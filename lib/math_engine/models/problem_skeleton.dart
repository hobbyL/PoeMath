// lib/math_engine/models/problem_skeleton.dart
//
// 应用题结构骨架：算法生成题目结构与答案，LLM 只负责套情境文本。
// 数学内容（操作数/运算符/答案）永远来自已验证的生成器，不采信 LLM。

import 'math_problem.dart';

/// 应用题知识点白名单。
enum WordProblemTopic {
  addition('加法'),
  subtraction('减法'),
  multiplication('乘法'),
  division('除法'),
  mixed('混合运算');

  const WordProblemTopic(this.label);
  final String label;

  /// 按枚举 name（如 'addition'）解析；未知值返回 null。
  /// 注意：不按中文 label 解析，label 仅用于 UI 展示与 prompt。
  static WordProblemTopic? tryParse(String value) {
    for (final topic in values) {
      if (topic.name == value) return topic;
    }
    return null;
  }
}

/// 应用题结构骨架（纯结构，无题面文本）。
///
/// 不变量：
/// - [operands] 全为非负整数（复用生成器保证）；
/// - [answer] 为非负整数，且等于 `ExpressionEvaluator.evaluate(
///   operands, operators)` 的结果（由生成器保证，入库前仍复算校验）。
class ProblemSkeleton {
  const ProblemSkeleton({
    required this.operands,
    required this.operators,
    required this.answer,
    required this.unitHint,
    required this.difficulty,
  });

  /// 操作数（全非负整数）。
  final List<int> operands;

  /// 运算符序列（长度 = operands.length - 1）。
  final List<Operator> operators;

  /// 整数答案（非负）。
  final int answer;

  /// 单位提示（个/支/颗/本/张/元/米/千克/朵/瓶）。
  final String unitHint;

  /// 难度（1-5，来自生成器 scoreDifficulty）。
  final int difficulty;

  /// 组装算式显示文本（如 "12 + 4 = ?"）。
  String get expressionText {
    final buffer = StringBuffer(operands.first.toString());
    for (var i = 0; i < operators.length; i++) {
      buffer.write(' ${operators[i].symbol} ${operands[i + 1]}');
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ProblemSkeleton &&
      _listEquals(operands, other.operands) &&
      _listEquals(operators, other.operators) &&
      answer == other.answer &&
      unitHint == other.unitHint &&
      difficulty == other.difficulty;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(operands), Object.hashAll(operators), answer,
          unitHint, difficulty,);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
