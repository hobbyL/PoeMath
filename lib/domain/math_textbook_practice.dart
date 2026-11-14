import 'dart:math';

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;
import 'package:poemath/math_engine/math_engine_api.dart';

typedef MathTextbookPracticeAvailability = ({
  Set<String> exerciseIds,
  Set<String> planIds,
  bool ready,
});

MathTextbookPracticeAvailability mathTextbookPracticeAvailability(
  MathTextbookLesson lesson,
  String bookId,
) {
  final learning = lesson.learning;
  if (learning == null) {
    return (exerciseIds: const {}, planIds: const {}, ready: false);
  }
  var automaticReady = lesson.isApproved(bookId);
  if (automaticReady) {
    try {
      learning.checkReady();
    } on FormatException {
      automaticReady = false;
    }
  }
  final exerciseIds = {
    for (final exercise in learning.exercises)
      if (automaticReady ||
          exercise.fields.isNotEmpty &&
              exercise.fields.every(
                (field) => field.rule.kind == MathTextbookAnswerKind.parent,
              ))
        exercise.id,
  };
  final planIds = {
    for (final plan in learning.practicePlans)
      if (automaticReady || plan.kind == MathTextbookPracticeKind.parentTask)
        plan.id,
  };
  return (
    exerciseIds: Set<String>.unmodifiable(exerciseIds),
    planIds: Set<String>.unmodifiable(planIds),
    ready:
        (learning.exercises.isNotEmpty || learning.practicePlans.isNotEmpty) &&
        exerciseIds.length == learning.exercises.length &&
        planIds.length == learning.practicePlans.length,
  );
}

class MathTextbookPracticeItem {
  MathTextbookPracticeItem({
    required this.exercise,
    required List<MathTextbookBlock> blocks,
    this.problem,
  }) : blocks = List.unmodifiable(blocks);
  final MathTextbookExercise exercise;
  final List<MathTextbookBlock> blocks;
  final MathProblem? problem;
  Map<String, dynamic> toJson() => {
    'exercise': exercise.toJson(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (problem != null) 'problem': problem!.toJson(),
  };
  factory MathTextbookPracticeItem.fromJson(Map<String, dynamic> raw) {
    final exercise = MathTextbookExercise.fromJson(raw['exercise']);
    final values = raw['blocks'];
    if (values is! List || values.length > 100) {
      throw const FormatException('练习来源无效');
    }
    final blocks = values.map(MathTextbookBlock.fromJson).toList();
    if (exercise.blockIds.any((id) => !blocks.any((b) => b.id == id))) {
      throw const FormatException('练习题缺少来源');
    }
    final problem = raw['problem'];
    return MathTextbookPracticeItem(
      exercise: exercise,
      blocks: blocks,
      problem: problem == null
          ? null
          : MathProblem.fromJson(problem as Map<String, dynamic>),
    );
  }
}

List<MathTextbookPracticeItem> originalMathTextbookItems(
  MathTextbookLesson lesson,
) => [
  for (final exercise in lesson.learning?.exercises ?? <MathTextbookExercise>[])
    MathTextbookPracticeItem(
      exercise: exercise,
      blocks: lesson.blocks
          .where((b) => exercise.blockIds.contains(b.id))
          .toList(),
    ),
];

List<MathTextbookPracticeItem> generateMathTextbookPractice({
  required MathTextbookLesson lesson,
  required MathTextbookPracticePlan plan,
  required int grade,
  required String semester,
  Random? random,
}) {
  final validated = MathTextbookPracticePlan.fromJson(plan.toJson());
  final knowledge = lesson.learning?.knowledgePoints
      .where((k) => k.id == validated.knowledgePointId)
      .firstOrNull;
  if (knowledge == null) throw const FormatException('巩固计划缺少本课知识点');
  final sources = lesson.blocks
      .where((b) => knowledge.blockIds.contains(b.id))
      .expand((b) => b.sources)
      .take(40)
      .toList();
  if (sources.isEmpty) throw const FormatException('巩固计划缺少原书来源');
  final rng = random ?? Random();
  final result = <MathTextbookPracticeItem>[];
  if (validated.kind == MathTextbookPracticeKind.engine) {
    final config = validated.config(grade, semester);
    final seen = <String>{};
    for (
      var attempts = 0;
      attempts < validated.count * 100 && result.length < validated.count;
      attempts++
    ) {
      final problem = MathEngine.generate(
        grade: grade,
        semester: semester,
        mode: validated.mode,
        skillId: validated.skillId,
        curriculum: config,
        random: rng,
      );
      if (ConstraintChecker.check(problem, config) != null ||
          problem.skillId != validated.skillId) {
        throw StateError('本课巩固超出已审核约束');
      }
      // 小范围可重复，但先尝试不同题；从不扩大本课数值范围。
      if (!seen.add(problem.problemText) && attempts < validated.count * 5) {
        continue;
      }
      final rule = problem.mode == ProblemMode.compare
          ? MathTextbookAnswerRule(
              kind: MathTextbookAnswerKind.comparison,
              expected: problem.answerText,
              answerSource: 'computed',
            )
          : problem.resultForm == ResultForm.withRemainder
          ? MathTextbookAnswerRule(
              kind: MathTextbookAnswerKind.remainder,
              expected: problem.answerText,
              divisor: problem.operands.last.asInteger,
              answerSource: 'computed',
            )
          : MathTextbookAnswerRule(
              kind: MathTextbookAnswerKind.number,
              expected: problem.result.toFractionString(),
              answerSource: 'computed',
            );
      result.add(
        _item(
          validated,
          result.length,
          problem.problemText,
          rule,
          sources,
          problem: problem,
        ),
      );
    }
  } else if (validated.kind == MathTextbookPracticeKind.parentTask) {
    result.add(
      _item(
        validated,
        0,
        validated.task,
        MathTextbookAnswerRule(
          kind: MathTextbookAnswerKind.parent,
          reference: knowledge.summary,
        ),
        sources,
      ),
    );
  } else {
    for (
      var attempts = 0;
      attempts < validated.count * 200 && result.length < validated.count;
      attempts++
    ) {
      final a =
          validated.minOperand +
          rng.nextInt(validated.maxOperand - validated.minOperand + 1);
      final b =
          validated.minOperand +
          rng.nextInt(validated.maxOperand - validated.minOperand + 1);
      final c =
          validated.minOperand +
          rng.nextInt(validated.maxOperand - validated.minOperand + 1);
      final unit = validated.unit.isEmpty
          ? '单位长度'
          : MathTextbookUnits.label(validated.unit);
      String question, answerUnit = '';
      NumberValue value;
      final pi = MathEngine.parseAnswer(validated.pi)!;
      switch (validated.kind) {
        case MathTextbookPracticeKind.unitConversion:
          final from = MathTextbookUnits.values[validated.unit]!,
              to = MathTextbookUnits.values[validated.toUnit]!;
          value = NumberValue.fromFraction(a * from.n * to.d, from.d * to.n);
          question =
              '$a${MathTextbookUnits.label(validated.unit)} = 多少${MathTextbookUnits.label(validated.toUnit)}？';
          answerUnit = validated.toUnit;
        case MathTextbookPracticeKind.rectanglePerimeter:
          value = NumberValue.fromInt((a + b) * 2);
          question = '长方形长 $a$unit，宽 $b$unit。周长是多少？';
          answerUnit = validated.unit;
        case MathTextbookPracticeKind.rectangleArea:
          value = NumberValue.fromInt(a * b);
          question = '长方形长 $a$unit，宽 $b$unit。面积是多少？';
          answerUnit = _powerUnit(validated.unit, 2);
        case MathTextbookPracticeKind.triangleArea:
          value = NumberValue.fromFraction(a * b, 2);
          question = '三角形底 $a$unit，高 $b$unit。面积是多少？';
          answerUnit = _powerUnit(validated.unit, 2);
        case MathTextbookPracticeKind.trapezoidArea:
          value = NumberValue.fromFraction((a + b) * c, 2);
          question = '梯形上底 $a$unit，下底 $b$unit，高 $c$unit。面积是多少？';
          answerUnit = _powerUnit(validated.unit, 2);
        case MathTextbookPracticeKind.circlePerimeter:
          value = NumberValue.fromInt(2 * a) * pi;
          question = '圆的半径是 $a$unit。取圆周率 ${validated.pi}，周长是多少？';
          answerUnit = validated.unit;
        case MathTextbookPracticeKind.circleArea:
          value = NumberValue.fromInt(a * a) * pi;
          question = '圆的半径是 $a$unit。取圆周率 ${validated.pi}，面积是多少？';
          answerUnit = _powerUnit(validated.unit, 2);
        case MathTextbookPracticeKind.cuboidVolume:
          value = NumberValue.fromInt(a * b * c);
          question = '长方体长 $a$unit、宽 $b$unit、高 $c$unit。体积是多少？';
          answerUnit = _powerUnit(validated.unit, 3);
        case MathTextbookPracticeKind.cubeVolume:
          value = NumberValue.fromInt(a * a * a);
          question = '正方体棱长 $a$unit。体积是多少？';
          answerUnit = _powerUnit(validated.unit, 3);
        case MathTextbookPracticeKind.cylinderVolume:
          value = NumberValue.fromInt(a * a * b) * pi;
          question = '圆柱底面半径 $a$unit，高 $b$unit。取圆周率 ${validated.pi}，体积是多少？';
          answerUnit = _powerUnit(validated.unit, 3);
        case MathTextbookPracticeKind.dataTable:
          final values = [a, b, c];
          if (validated.task == 'mean') {
            value = NumberValue.fromFraction(a + b + c, 3);
            question = '统计表：甲 $a、乙 $b、丙 $c。平均数是多少？';
          } else if (validated.task == 'max') {
            value = NumberValue.fromInt(values.reduce(max));
            question = '统计表：甲 $a、乙 $b、丙 $c。最大值是多少？';
          } else if (validated.task == 'difference') {
            value = NumberValue.fromInt(
              values.reduce(max) - values.reduce(min),
            );
            question = '统计表：甲 $a、乙 $b、丙 $c。最大值与最小值相差多少？';
          } else {
            value = NumberValue.fromInt(a + b + c);
            question = '统计表：甲 $a、乙 $b、丙 $c。合计是多少？';
          }
        case MathTextbookPracticeKind.engine:
        case MathTextbookPracticeKind.parentTask:
          throw StateError('巩固类型处理错误');
      }
      if (value.asDouble.abs() > validated.maxResult) continue;
      result.add(
        _item(
          validated,
          result.length,
          question,
          MathTextbookAnswerRule(
            kind: MathTextbookAnswerKind.number,
            expected: value.toFractionString(),
            unit: answerUnit,
            allowUnitConversion: answerUnit.isNotEmpty,
            answerSource: 'computed',
          ),
          sources,
        ),
      );
    }
  }
  if (result.isEmpty ||
      validated.kind != MathTextbookPracticeKind.parentTask &&
          result.length != validated.count) {
    throw StateError('无法生成符合本课范围的巩固题，请家长调整已核对的计划');
  }
  return result;
}

String _powerUnit(String unit, int power) {
  if (unit.isEmpty) return '';
  final target = '$unit${power == 2 ? '²' : '³'}';
  if (!MathTextbookUnits.values.containsKey(target)) {
    throw const FormatException('本机暂不支持这个面积或体积单位');
  }
  return target;
}

String mathTextbookReadingDigest(MathTextbookLesson lesson) =>
    textbookContentDigest({
      'title': lesson.title,
      'blocks': lesson.blocks.map((b) => b.toJson()).toList(),
      'knowledgePoints': lesson.learning?.knowledgePoints
          .map((k) => k.toJson())
          .toList(),
    });

/// 进度按具体目标比较；同课其他题改动不抹掉仍匹配的已完成目标。
String mathTextbookTargetDigest(
  MathTextbookLesson lesson,
  String? planId,
  String exerciseId,
) {
  final learning = lesson.learning;
  if (learning == null) throw const FormatException('本课尚未配置学习内容');
  final plan = planId == null
      ? null
      : learning.practicePlans.where((p) => p.id == planId).firstOrNull;
  final exercise = planId == null
      ? learning.exercises.where((e) => e.id == exerciseId).firstOrNull
      : null;
  if (planId != null && plan == null || planId == null && exercise == null) {
    throw const FormatException('本课学习目标已移除');
  }
  final knowledgeIds = plan == null
      ? exercise!.knowledgePointIds.toSet()
      : {plan.knowledgePointId};
  final knowledge = learning.knowledgePoints
      .where((k) => knowledgeIds.contains(k.id))
      .toList();
  final blockIds = {
    ...?exercise?.blockIds,
    ...knowledge.expand((k) => k.blockIds),
  };
  return textbookContentDigest({
    'exercise': exercise?.toJson(),
    'plan': plan?.toJson(),
    'knowledge': knowledge.map((k) => k.toJson()).toList(),
    'blocks': lesson.blocks
        .where((b) => blockIds.contains(b.id))
        .map((b) => b.toJson())
        .toList(),
  });
}

MathTextbookPracticeItem _item(
  MathTextbookPracticePlan plan,
  int index,
  String question,
  MathTextbookAnswerRule rule,
  List<MathTextbookRegion> sources, {
  MathProblem? problem,
}) {
  final block = MathTextbookBlock(
    id: '${plan.id}-q-$index',
    kind: MathTextbookBlockKind.text,
    spans: problem == null
        ? [MathTextbookSpan.text(question)]
        : _engineSpans(question),
    sources: sources,
  );
  return MathTextbookPracticeItem(
    exercise: MathTextbookExercise(
      id: '${plan.id}-$index',
      title: '本课巩固 ${index + 1}',
      blockIds: [block.id],
      knowledgePointIds: [plan.knowledgePointId],
      fields: [
        MathTextbookAnswerField(id: 'answer', label: '你的答案', rule: rule),
      ],
    ),
    blocks: [block],
    problem: problem,
  );
}

List<MathTextbookSpan> _engineSpans(String text) {
  final spans = <MathTextbookSpan>[];
  var offset = 0;
  for (final match in RegExp(r'(?<![.\d])([+-]?\d+)/(\d+)').allMatches(text)) {
    if (match.start > offset) {
      spans.add(MathTextbookSpan.text(text.substring(offset, match.start)));
    }
    spans.add(
      MathTextbookSpan.math(
        MathTextbookFraction(match.group(1)!, match.group(2)!),
      ),
    );
    offset = match.end;
  }
  if (offset < text.length) {
    spans.add(MathTextbookSpan.text(text.substring(offset)));
  }
  return spans;
}
