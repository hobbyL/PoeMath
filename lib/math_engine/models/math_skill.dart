import 'math_problem.dart';

/// 永久存储标识；文案可变，id 不随界面翻译变化。
enum MathSkill {
  addition('addition', '整数加法'),
  additionCarry('addition_carry', '进位加法'),
  subtraction('subtraction', '整数减法'),
  subtractionBorrow('subtraction_borrow', '退位减法'),
  multiplicationTable('multiplication_table', '乘法口诀'),
  remainderDivision('remainder_division', '有余数除法'),
  multiplication('multiplication', '多位数乘法'),
  division('division', '整除计算'),
  operationOrder('operation_order', '混合运算顺序'),
  operationLaw('operation_law', '运算律'),
  decimal('decimal', '小数运算'),
  fraction('fraction', '分数运算'),
  percentage('percentage', '百分数'),
  equation('equation', '简易方程'),
  ratio('ratio', '比与比例'),
  negative('negative', '正负数');

  const MathSkill(this.id, this.label);
  final String id;
  final String label;

  static MathSkill? fromId(String? id) =>
      values.where((value) => value.id == id).firstOrNull;

  /// 任意一列存在进位/退位；必须为两个非负整数的单步题。
  static bool hasRegrouping(MathProblem problem) {
    if (problem.operands.length != 2 ||
        problem.operators.length != 1 ||
        problem.operands.any((n) => !n.isInteger || n.isNegative)) {
      return false;
    }
    var a = problem.operands[0].asInteger;
    var b = problem.operands[1].asInteger;
    while (a > 0 || b > 0) {
      if (problem.operators.single == Operator.add && a % 10 + b % 10 >= 10) {
        return true;
      }
      if (problem.operators.single == Operator.subtract && a % 10 < b % 10) {
        return true;
      }
      a ~/= 10;
      b ~/= 10;
    }
    return false;
  }
}
