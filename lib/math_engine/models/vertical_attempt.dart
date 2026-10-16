import 'math_problem.dart';
import 'answer_judgement.dart';

/// 两位数加减法的逐列作答。空白和明确填写 0 含义不同。
class VerticalAttempt {
  static const errorCategory = 'vertical_process';
  const VerticalAttempt({
    this.ones = '',
    this.tens = '',
    this.hundreds = '',
    this.regroup = '',
  });
  final String ones;
  final String tens;
  final String hundreds;
  final String regroup;

  static bool supports(MathProblem problem) =>
      problem.mode == ProblemMode.vertical &&
      problem.displayText == null &&
      problem.operands.length == 2 &&
      problem.operators.length == 1 &&
      [Operator.add, Operator.subtract].contains(problem.operators.single) &&
      problem.operands.every(
        (n) => n.isInteger && n.asInteger >= 10 && n.asInteger <= 99,
      ) &&
      problem.result.isInteger &&
      !problem.result.isNegative;

  static bool needsHundreds(MathProblem problem) =>
      problem.result.asInteger >= 100;
  static bool _digit(String value) => RegExp(r'^\d$').hasMatch(value);
  bool complete(MathProblem problem) =>
      _digit(ones) &&
      _digit(tens) &&
      _digit(regroup) &&
      (!needsHundreds(problem) || _digit(hundreds));
  String answer(MathProblem problem) =>
      '${needsHundreds(problem) ? hundreds : ''}$tens$ones';

  VerticalAttempt withField(String field, String value) => VerticalAttempt(
        ones: field == 'ones' ? value : ones,
        tens: field == 'tens' ? value : tens,
        hundreds: field == 'hundreds' ? value : hundreds,
        regroup: field == 'regroup' ? value : regroup,
      );
  String field(String key) => switch (key) {
        'ones' => ones,
        'tens' => tens,
        'hundreds' => hundreds,
        'regroup' => regroup,
        _ => throw ArgumentError.value(key),
      };
  Map<String, dynamic> toJson() => {
        'v': 1,
        'ones': ones,
        'tens': tens,
        'hundreds': hundreds,
        'regroup': regroup,
      };
  factory VerticalAttempt.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) throw const FormatException('不支持的竖式作答');
    final result = VerticalAttempt(
      ones: json['ones'] as String,
      tens: json['tens'] as String,
      hundreds: json['hundreds'] as String,
      regroup: json['regroup'] as String,
    );
    if ([result.ones, result.tens, result.hundreds, result.regroup]
        .any((s) => s.isNotEmpty && !_digit(s))) {
      throw const FormatException('竖式各列只能填写一位数字');
    }
    return result;
  }

  AnswerJudgement judge(MathProblem problem) {
    if (!supports(problem)) throw ArgumentError('此题不支持逐列过程练习');
    final a = problem.operands[0].asInteger;
    final b = problem.operands[1].asInteger;
    final add = problem.operators.single == Operator.add;
    final carry = add ? (a % 10 + b % 10) ~/ 10 : (a % 10 < b % 10 ? 1 : 0);
    final onesCalculation =
        add ? a % 10 + b % 10 : a % 10 + carry * 10 - b % 10;
    final tensCalculation =
        add ? a ~/ 10 + b ~/ 10 + carry : a ~/ 10 - carry - b ~/ 10;
    final correct = complete(problem) &&
        int.parse(ones) == onesCalculation % 10 &&
        int.parse(tens) == tensCalculation % 10 &&
        int.parse(regroup) == carry &&
        (!needsHundreds(problem) ||
            int.parse(hundreds) == tensCalculation ~/ 10);
    return AnswerJudgement(
      isCorrect: correct,
      diagnosis: correct
          ? null
          : const MistakeDiagnosis(
              category: errorCategory,
              template: '请同时检查个位、十位和进退位记录。结果相同也需要过程正确。',
            ),
      correctSteps: [
        SolutionStep(
          description: add ? '先算个位，满十向十位进 1' : '先算个位，不够减向十位借 1',
          expression: add
              ? '${a % 10} + ${b % 10}'
              : '${a % 10} + ${carry * 10} − ${b % 10}',
          resultHint:
              '个位写 ${onesCalculation % 10}，${add ? '进位' : '借位'}记 $carry',
        ),
        SolutionStep(
          description: add ? '十位相加，再加上进位' : '十位先减去借出的 1，再相减',
          expression: add
              ? '${a ~/ 10} + ${b ~/ 10} + $carry'
              : '${a ~/ 10} − $carry − ${b ~/ 10}',
          resultHint:
              '十位写 ${tensCalculation % 10}${needsHundreds(problem) ? '，百位写 ${tensCalculation ~/ 10}' : ''}',
        ),
      ],
    );
  }
}
