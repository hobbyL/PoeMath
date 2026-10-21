import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'expression_evaluator.dart';

/// 旧讲解的完整整数等式检查。不能截取复合算式中的二元子串。
class WordProblemEquations {
  const WordProblemEquations._();

  static bool hasInvalidEquation(String text) {
    var normalized = text
        .replaceAll('−', '-')
        .replaceAll('－', '-')
        .replaceAll('＊', '×')
        .replaceAll('*', '×')
        .replaceAll('／', '÷')
        .replaceAll('/', '÷')
        .replaceAll('＋', '+')
        .replaceAll('＝', '=');
    normalized = normalized.replaceAllMapped(
      RegExp(r'\d+(?:(?:加|减|乘以|乘|除以|除)\d+)+(?:等于\d+)+'),
      (m) => m[0]!
          .replaceAll('乘以', '×')
          .replaceAll('除以', '÷')
          .replaceAll('加', '+')
          .replaceAll('减', '-')
          .replaceAll('乘', '×')
          .replaceAll('除', '÷')
          .replaceAll('等于', '='),
    );
    normalized = normalized.replaceAll('\n', '；').replaceAll('\r', '；');
    for (final match in RegExp(r'[\d\s+\-×÷=()]+').allMatches(normalized)) {
      final expression = match[0]!.trim();
      if (!expression.contains('=')) continue;
      final sides = expression.split('=');
      Fraction? expected;
      for (final side in sides) {
        final value = _evaluate(side.trim());
        if (value == null || expected != null && value != expected) return true;
        expected = value;
      }
    }
    return false;
  }

  static Fraction? _evaluate(String expression) {
    // 旧整数骨架不含括号；未知数学格式不作为通过依据。
    final tokens = RegExp(r'\d+|[+\-×÷]')
        .allMatches(expression)
        .map((m) => m[0]!)
        .toList();
    if (tokens.join() != expression.replaceAll(RegExp(r'\s'), '') ||
        tokens.isEmpty) {
      return null;
    }
    final operands = <NumberValue>[];
    final operators = <Operator>[];
    var expectsNumber = true;
    var sign = 1;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (expectsNumber) {
        if ((token == '-' || token == '+') &&
            sign == 1 &&
            i + 1 < tokens.length) {
          final number = int.tryParse(tokens[++i]);
          if (number == null) return null;
          sign = token == '-' ? -1 : 1;
          operands.add(NumberValue.fromInt(sign * number));
        } else {
          final number = int.tryParse(token);
          if (number == null) return null;
          operands.add(NumberValue.fromInt(number));
        }
        sign = 1;
      } else {
        final op = switch (token) {
          '+' => Operator.add,
          '-' => Operator.subtract,
          '×' => Operator.multiply,
          '÷' => Operator.divide,
          _ => null,
        };
        if (op == null) return null;
        operators.add(op);
      }
      expectsNumber = !expectsNumber;
    }
    if (expectsNumber) return null;
    return ExpressionEvaluator.evaluate(operands, operators);
  }
}
