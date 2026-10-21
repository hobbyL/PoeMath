import 'math_problem.dart';
import 'answer_judgement.dart';
import '../step_solver/step_solver.dart';

/// 整数竖式的结果逐列作答。空白和明确填写 0 含义不同。
class VerticalAttempt {
  static const errorCategory = 'vertical_process';
  const VerticalAttempt({
    this.ones = '',
    this.tens = '',
    this.hundreds = '',
    this.regroup = '',
    this.higherDigits = const {},
  });
  final String ones;
  final String tens;
  final String hundreds;

  /// 保留旧草稿和错题的进退位记录，不参与结果判分。
  final String regroup;
  final Map<String, String> higherDigits;

  static const _resultFields = [
    ('ones', '个位'),
    ('tens', '十位'),
    ('hundreds', '百位'),
    ('thousands', '千位'),
    ('tenThousands', '万位'),
    ('hundredThousands', '十万位'),
    ('millions', '百万位'),
    ('tenMillions', '千万位'),
    ('hundredMillions', '亿位'),
    ('billions', '十亿位'),
    ('tenBillions', '百亿位'),
    ('hundredBillions', '千亿位'),
    ('trillions', '万亿位'),
    ('tenTrillions', '十万亿位'),
    ('hundredTrillions', '百万亿位'),
    ('quadrillions', '千万亿位'),
  ];

  static bool supports(MathProblem problem) =>
      problem.mode == ProblemMode.vertical &&
      problem.displayText == null &&
      problem.operands.length == 2 &&
      problem.operators.length == 1 &&
      [Operator.add, Operator.subtract, Operator.multiply]
          .contains(problem.operators.single) &&
      problem.operands.every(
        (n) => n.isInteger && !n.isNegative,
      ) &&
      problem.resultForm == ResultForm.integer &&
      problem.result.isInteger &&
      !problem.result.isNegative &&
      problem.result.asInteger.toString().length <= _resultFields.length;

  /// 专项生成仍限定两位数加减法，与通用整数竖式输入能力分开。
  static bool supportsProcess(MathProblem problem) =>
      supports(problem) &&
      [Operator.add, Operator.subtract].contains(problem.operators.single) &&
      problem.operands.every((n) => n.asInteger >= 10 && n.asInteger <= 99);

  /// 从高位到低位展示结果数位，个位和十位始终保留。
  static List<(String, String)> fieldsFor(MathProblem problem) {
    final length = problem.result.asInteger.toString().length;
    return _resultFields
        .take(length < 2 ? 2 : length)
        .toList()
        .reversed
        .toList();
  }

  static bool needsHundreds(MathProblem problem) =>
      problem.result.asInteger >= 100;
  static bool _digit(String value) => RegExp(r'^\d$').hasMatch(value);
  bool complete(MathProblem problem) =>
      fieldsFor(problem).every((entry) => _digit(field(entry.$1)));
  String answer(MathProblem problem) =>
      fieldsFor(problem).map((entry) => field(entry.$1)).join();

  VerticalAttempt withField(String field, String value) => VerticalAttempt(
        ones: field == 'ones' ? value : ones,
        tens: field == 'tens' ? value : tens,
        hundreds: field == 'hundreds' ? value : hundreds,
        regroup: field == 'regroup' ? value : regroup,
        higherDigits: {
          ...higherDigits,
          if (_resultFields.skip(3).any((entry) => entry.$1 == field))
            field: value,
        },
      );
  String field(String key) => switch (key) {
        'ones' => ones,
        'tens' => tens,
        'hundreds' => hundreds,
        'regroup' => regroup,
        _ when _resultFields.skip(3).any((entry) => entry.$1 == key) =>
          higherDigits[key] ?? '',
        _ => throw ArgumentError.value(key),
      };
  Map<String, dynamic> toJson() => {
        'v': 1,
        'ones': ones,
        'tens': tens,
        'hundreds': hundreds,
        'regroup': regroup,
        if (higherDigits.isNotEmpty) 'higherDigits': higherDigits,
      };
  factory VerticalAttempt.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) throw const FormatException('不支持的竖式作答');
    final result = VerticalAttempt(
      ones: json['ones'] as String,
      tens: json['tens'] as String,
      hundreds: json['hundreds'] as String,
      regroup: json['regroup'] as String? ?? '',
      higherDigits: (json['higherDigits'] as Map<String, dynamic>?)
              ?.map((key, value) => MapEntry(key, value as String)) ??
          const {},
    );
    if (result.higherDigits.keys.any(
          (key) => !_resultFields.skip(3).any((entry) => entry.$1 == key),
        ) ||
        [
          result.ones,
          result.tens,
          result.hundreds,
          result.regroup,
          ...result.higherDigits.values,
        ].any((s) => s.isNotEmpty && !_digit(s))) {
      throw const FormatException('竖式各列只能填写一位数字');
    }
    return result;
  }

  AnswerJudgement judge(MathProblem problem) {
    if (!supports(problem)) throw ArgumentError('此题不支持整数竖式逐列作答');
    final correct = complete(problem) &&
        int.parse(answer(problem)) == problem.result.asInteger;
    if (!supportsProcess(problem)) {
      return AnswerJudgement(
        isCorrect: correct,
        diagnosis: correct
            ? null
            : const MistakeDiagnosis(
                category: errorCategory,
                template: '请检查结果的各数位。',
              ),
        correctSteps: StepSolver.solve(problem),
      );
    }
    final a = problem.operands[0].asInteger;
    final b = problem.operands[1].asInteger;
    final add = problem.operators.single == Operator.add;
    final carry = add ? (a % 10 + b % 10) ~/ 10 : (a % 10 < b % 10 ? 1 : 0);
    final onesCalculation =
        add ? a % 10 + b % 10 : a % 10 + carry * 10 - b % 10;
    final tensCalculation =
        add ? a ~/ 10 + b ~/ 10 + carry : a ~/ 10 - carry - b ~/ 10;
    return AnswerJudgement(
      isCorrect: correct,
      diagnosis: correct
          ? null
          : const MistakeDiagnosis(
              category: errorCategory,
              template: '请检查结果的各数位，计算时注意进位或借位。',
            ),
      correctSteps: [
        SolutionStep(
          description: add ? '先算个位，满十向十位进 1' : '先算个位，不够减向十位借 1',
          expression: add
              ? '${a % 10} + ${b % 10}'
              : '${a % 10} + ${carry * 10} − ${b % 10}',
          resultHint:
              '个位写 ${onesCalculation % 10}，${carry == 0 ? (add ? '无需进位' : '无需借位') : (add ? '向十位进 1' : '向十位借 1')}',
        ),
        SolutionStep(
          description: add
              ? '十位相加，再加上进位'
              : carry == 0
                  ? '十位相减'
                  : '十位先减去借出的 1，再相减',
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
