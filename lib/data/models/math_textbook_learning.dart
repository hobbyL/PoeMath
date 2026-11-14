part of 'math_textbook_course.dart';

enum MathTextbookAnswerKind {
  number,
  choice,
  comparison,
  remainder,
  expression,
  parent,
}

enum MathTextbookNumberForm {
  any,
  integer,
  decimal,
  fraction,
  simplestFraction,
  mixedNumber,
  percentage,
}

enum MathTextbookPracticeKind {
  engine,
  unitConversion,
  rectanglePerimeter,
  rectangleArea,
  triangleArea,
  trapezoidArea,
  circlePerimeter,
  circleArea,
  cuboidVolume,
  cubeVolume,
  cylinderVolume,
  dataTable,
  parentTask,
}

enum MathTextbookResult {
  correct,
  incorrect,
  pendingParent,
  parentCorrect,
  parentAgain,
}

/// 单位使用明确的量纲与精确换算比例，屏幕上测量不能成为自动判分依据。
class MathTextbookUnits {
  static const values = <String, ({String dimension, int n, int d})>{
    'mm': (dimension: 'length', n: 1, d: 1000),
    'cm': (dimension: 'length', n: 1, d: 100),
    'dm': (dimension: 'length', n: 1, d: 10),
    'm': (dimension: 'length', n: 1, d: 1),
    'km': (dimension: 'length', n: 1000, d: 1),
    'mm²': (dimension: 'area', n: 1, d: 1000000),
    'cm²': (dimension: 'area', n: 1, d: 10000),
    'dm²': (dimension: 'area', n: 1, d: 100),
    'm²': (dimension: 'area', n: 1, d: 1),
    '公顷': (dimension: 'area', n: 10000, d: 1),
    'km²': (dimension: 'area', n: 1000000, d: 1),
    'cm³': (dimension: 'volume', n: 1, d: 1000000),
    'dm³': (dimension: 'volume', n: 1, d: 1000),
    'm³': (dimension: 'volume', n: 1, d: 1),
    'mL': (dimension: 'volume', n: 1, d: 1000000),
    'L': (dimension: 'volume', n: 1, d: 1000),
    'g': (dimension: 'mass', n: 1, d: 1000),
    'kg': (dimension: 'mass', n: 1, d: 1),
    't': (dimension: 'mass', n: 1000, d: 1),
    '秒': (dimension: 'time', n: 1, d: 1),
    '分钟': (dimension: 'time', n: 60, d: 1),
    '小时': (dimension: 'time', n: 3600, d: 1),
    '分': (dimension: 'money', n: 1, d: 100),
    '角': (dimension: 'money', n: 1, d: 10),
    '元': (dimension: 'money', n: 1, d: 1),
  };
  static const labels = {
    'mm': '毫米',
    'cm': '厘米',
    'dm': '分米',
    'm': '米',
    'km': '千米',
    'mm²': '平方毫米',
    'cm²': '平方厘米',
    'dm²': '平方分米',
    'm²': '平方米',
    'km²': '平方千米',
    'cm³': '立方厘米',
    'dm³': '立方分米',
    'm³': '立方米',
    'mL': '毫升',
    'L': '升',
    'g': '克',
    'kg': '千克',
    't': '吨',
  };
  static String label(String unit) => labels[unit] ?? unit;
  static String normalize(String value) {
    final text = value.trim().replaceAll('2', '²').replaceAll('3', '³');
    return labels.entries
            .where((entry) => entry.value == text)
            .firstOrNull
            ?.key ??
        text;
  }
}

class MathTextbookAnswerRule {
  MathTextbookAnswerRule({
    required this.kind,
    this.expected = '',
    this.form = MathTextbookNumberForm.any,
    this.unit = '',
    this.allowUnitConversion = false,
    this.divisor,
    List<String> options = const [],
    List<String> correctChoices = const [],
    this.reference = '',
    this.answerSource = 'parent',
  }) : options = List.unmodifiable(options),
       correctChoices = List.unmodifiable(correctChoices);
  final MathTextbookAnswerKind kind;
  final String expected;
  final MathTextbookNumberForm form;
  final String unit;
  final bool allowUnitConversion;
  final int? divisor;
  final List<String> options;
  final List<String> correctChoices;
  final String reference;
  final String answerSource;

  static NumberValue? numberValue(String value) {
    final text = value.trim().replaceAll('−', '-');
    final percent = text.endsWith('%') || text.endsWith('％');
    final number = MathEngine.parseAnswer(
      percent ? text.substring(0, text.length - 1) : text,
    );
    if (number == null) return null;
    if (!percent) return number;
    final fraction = number.asFraction;
    final n = BigInt.from(fraction.numerator),
        d = BigInt.from(fraction.denominator) * BigInt.from(100);
    final gcd = n.gcd(d), max = BigInt.from(9007199254740991);
    if ((n ~/ gcd).abs() > max || (d ~/ gcd).abs() > max) return null;
    return NumberValue.fromFraction((n ~/ gcd).toInt(), (d ~/ gcd).toInt());
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'expected': expected,
    'form': form.name,
    'unit': unit,
    'allowUnitConversion': allowUnitConversion,
    'divisor': divisor,
    'options': options,
    'correctChoices': correctChoices,
    'reference': reference,
    'answerSource': answerSource,
  };
  factory MathTextbookAnswerRule.fromJson(Object? value) {
    final raw = _object(value, '答案规则');
    final kind = _enum(MathTextbookAnswerKind.values, raw['kind'], '作答方式');
    final expected = _string(
      raw['expected'] ?? '',
      '答案',
      max: 128,
      empty: true,
    );
    final options = _strings(raw['options'] ?? [], '选项', 30, 500);
    final choices = _strings(raw['correctChoices'] ?? [], '正确选项', 30, 500);
    final form = _enum(
      MathTextbookNumberForm.values,
      raw['form'] ?? 'any',
      '表示要求',
    );
    final unit = _string(raw['unit'] ?? '', '单位', max: 30, empty: true);
    if (unit.isNotEmpty && !MathTextbookUnits.values.containsKey(unit)) {
      throw const FormatException('单位不支持');
    }
    final convert = _boolean(raw['allowUnitConversion'] ?? false, '单位换算');
    final divisor = raw['divisor'] == null
        ? null
        : _integer(raw['divisor'], '除数', min: 1, max: 1000000000);
    switch (kind) {
      case MathTextbookAnswerKind.number:
      case MathTextbookAnswerKind.expression:
        if (numberValue(expected) == null) {
          throw const FormatException('自动判分必须填写可验证的数值答案');
        }
      case MathTextbookAnswerKind.choice:
        if (options.length < 2 ||
            choices.isEmpty ||
            choices.any((v) => !options.contains(v))) {
          throw const FormatException('请填写选项及其中的正确选项');
        }
      case MathTextbookAnswerKind.comparison:
        if (!const ['<', '=', '>'].contains(expected)) {
          throw const FormatException('比较答案须为 <、= 或 >');
        }
      case MathTextbookAnswerKind.remainder:
        final values = expected.split('…');
        final q = values.length == 2 ? int.tryParse(values[0]) : null;
        final r = values.length == 2 ? int.tryParse(values[1]) : null;
        if (divisor == null ||
            q == null ||
            q < 0 ||
            r == null ||
            r < 0 ||
            r >= divisor) {
          throw const FormatException('商余答案须为 商…余数，余数小于除数');
        }
      case MathTextbookAnswerKind.parent:
        break;
    }
    if (options.toSet().length != options.length ||
        choices.toSet().length != choices.length) {
      throw const FormatException('选项重复');
    }
    final source = _string(raw['answerSource'] ?? 'parent', '答案来源', max: 20);
    if (!const ['parent', 'source', 'computed'].contains(source)) {
      throw const FormatException('答案来源无效');
    }
    return MathTextbookAnswerRule(
      kind: kind,
      expected: expected,
      form: form,
      unit: unit,
      allowUnitConversion: convert,
      divisor: divisor,
      options: options,
      correctChoices: choices,
      reference: _string(
        raw['reference'] ?? '',
        '核对参考',
        max: 5000,
        empty: true,
      ),
      answerSource: source,
    );
  }
}

class MathTextbookAnswerField {
  const MathTextbookAnswerField({
    required this.id,
    required this.label,
    required this.rule,
  });
  final String id;
  final String label;
  final MathTextbookAnswerRule rule;
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'rule': rule.toJson(),
  };
  factory MathTextbookAnswerField.fromJson(Object? value) {
    final raw = _object(value, '作答项');
    return MathTextbookAnswerField(
      id: _identifier(raw['id']),
      label: _string(raw['label'], '作答提示', max: 200),
      rule: MathTextbookAnswerRule.fromJson(raw['rule']),
    );
  }
}

class MathTextbookExercise {
  MathTextbookExercise({
    required this.id,
    required this.title,
    required List<String> blockIds,
    required List<MathTextbookAnswerField> fields,
    List<String> knowledgePointIds = const [],
    this.number = '',
    this.note = '',
  }) : blockIds = List.unmodifiable(blockIds),
       fields = List.unmodifiable(fields),
       knowledgePointIds = List.unmodifiable(knowledgePointIds);
  final String id;
  final String title;
  final String number;
  final String note;
  final List<String> blockIds;
  final List<String> knowledgePointIds;
  final List<MathTextbookAnswerField> fields;
  bool get needsParent =>
      fields.any((field) => field.rule.kind == MathTextbookAnswerKind.parent);
  String get digest => textbookContentDigest(toJson());
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'number': number,
    'note': note,
    'blockIds': blockIds,
    'knowledgePointIds': knowledgePointIds,
    'fields': fields.map((f) => f.toJson()).toList(),
  };
  factory MathTextbookExercise.fromJson(Object? value) {
    final raw = _object(value, '原书题目');
    final blocks = _strings(raw['blockIds'], '题目来源', 100, 160);
    final fields = _list(
      raw['fields'],
      '作答项',
      max: 100,
    ).map(MathTextbookAnswerField.fromJson).toList();
    if (blocks.isEmpty ||
        fields.isEmpty ||
        fields.map((f) => f.id).toSet().length != fields.length) {
      throw const FormatException('题目须有来源和不重复的作答项');
    }
    return MathTextbookExercise(
      id: _identifier(raw['id']),
      title: _string(raw['title'], '题目提示', max: 500),
      number: _string(raw['number'] ?? '', '原书题号', max: 40, empty: true),
      note: _string(raw['note'] ?? '', '题目说明', max: 5000, empty: true),
      blockIds: blocks,
      fields: fields,
      knowledgePointIds: _strings(
        raw['knowledgePointIds'] ?? [],
        '题目知识点',
        30,
        160,
      ),
    );
  }
}

class MathTextbookKnowledgePoint {
  MathTextbookKnowledgePoint({
    required this.id,
    required this.title,
    this.summary = '',
    required List<String> blockIds,
  }) : blockIds = List.unmodifiable(blockIds);
  final String id;
  final String title;
  final String summary;
  final List<String> blockIds;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'blockIds': blockIds,
  };
  factory MathTextbookKnowledgePoint.fromJson(Object? value) {
    final raw = _object(value, '知识点');
    final blocks = _strings(raw['blockIds'], '知识点来源', 100, 160);
    if (blocks.isEmpty) throw const FormatException('知识点须保留原书来源');
    return MathTextbookKnowledgePoint(
      id: _identifier(raw['id']),
      title: _string(raw['title'], '知识点名称', max: 200),
      summary: _string(raw['summary'] ?? '', '知识要点', max: 5000, empty: true),
      blockIds: blocks,
    );
  }
}

class MathTextbookPracticePlan {
  MathTextbookPracticePlan({
    required this.id,
    required this.knowledgePointId,
    required this.title,
    required this.kind,
    this.skillId,
    this.count = 5,
    this.minOperand = 0,
    this.maxOperand = 20,
    this.maxResult = 40,
    Set<Operator> operators = const {Operator.add, Operator.subtract},
    this.mode,
    this.allowCarry = true,
    this.allowBorrow = true,
    this.allowRemainder = false,
    this.allowBrackets = false,
    this.allowNegative = false,
    this.decimalPlaces = 0,
    this.maxDenominator = 1,
    this.unit = '',
    this.toUnit = '',
    this.pi = '3.14',
    this.task = '',
  }) : operators = Set.unmodifiable(operators);
  final String id, knowledgePointId, title;
  final MathTextbookPracticeKind kind;
  final String? skillId;
  final int count,
      minOperand,
      maxOperand,
      maxResult,
      decimalPlaces,
      maxDenominator;
  final Set<Operator> operators;
  final ProblemMode? mode;
  final bool allowCarry,
      allowBorrow,
      allowRemainder,
      allowBrackets,
      allowNegative;
  final String unit, toUnit, pi, task;
  String get digest => textbookContentDigest(toJson());
  GradeConfig config(int grade, String semester) => GradeConfig(
    grade: grade,
    semester: semester,
    label: title,
    allowedOperators: operators,
    allowedModes: mode == null
        ? {
            ProblemMode.findResult,
            ProblemMode.findMissing,
            ProblemMode.compare,
            ProblemMode.chain,
            if (allowBrackets) ProblemMode.withBrackets,
          }
        : {mode!},
    minOperand: minOperand,
    maxOperand: maxOperand,
    maxResult: maxResult,
    allowCarry: allowCarry,
    allowBorrow: allowBorrow,
    allowRemainder: allowRemainder,
    allowBrackets: allowBrackets,
    allowNegative: allowNegative,
    allowDecimal: decimalPlaces > 0,
    maxDecimalPlaces: decimalPlaces,
    allowFraction: maxDenominator > 1,
    maxDenominator: maxDenominator,
    maxMultiplier: maxOperand,
    maxDividend: maxOperand,
    maxOperands: allowBrackets ? 4 : 3,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'knowledgePointId': knowledgePointId,
    'title': title,
    'kind': kind.name,
    'skillId': skillId,
    'count': count,
    'minOperand': minOperand,
    'maxOperand': maxOperand,
    'maxResult': maxResult,
    'operators': operators.map((o) => o.name).toList(),
    'mode': mode?.name,
    'allowCarry': allowCarry,
    'allowBorrow': allowBorrow,
    'allowRemainder': allowRemainder,
    'allowBrackets': allowBrackets,
    'allowNegative': allowNegative,
    'decimalPlaces': decimalPlaces,
    'maxDenominator': maxDenominator,
    'unit': unit,
    'toUnit': toUnit,
    'pi': pi,
    'task': task,
  };
  factory MathTextbookPracticePlan.fromJson(Object? value) {
    final raw = _object(value, '本课巩固计划');
    final kind = _enum(MathTextbookPracticeKind.values, raw['kind'], '巩固方式');
    final skill = raw['skillId'] == null
        ? null
        : _string(raw['skillId'], '知识点标识', max: 80);
    if (kind == MathTextbookPracticeKind.engine &&
        MathSkill.fromId(skill) == null) {
      throw const FormatException('引擎巩固须选择已支持知识点');
    }
    final ops = _list(
      raw['operators'] ?? ['add', 'subtract'],
      '巩固运算',
      max: 4,
    ).map((v) => _enum(Operator.values, v, '运算')).toSet();
    final minimum = _integer(
      raw['minOperand'] ?? 0,
      '最小数',
      min: -1000000,
      max: 1000000,
    );
    final maximum = _integer(
      raw['maxOperand'] ?? 20,
      '最大数',
      min: minimum,
      max: 1000000,
    );
    final unit = _string(raw['unit'] ?? '', '巩固单位', max: 30, empty: true),
        toUnit = _string(raw['toUnit'] ?? '', '目标单位', max: 30, empty: true);
    final task = _string(raw['task'] ?? '', '巩固任务', max: 5000, empty: true);
    if (kind == MathTextbookPracticeKind.parentTask && task.trim().isEmpty) {
      throw const FormatException('家长核对巩固须填写实际任务');
    }
    if (kind == MathTextbookPracticeKind.unitConversion &&
        (MathTextbookUnits.values[unit] == null ||
            MathTextbookUnits.values[toUnit] == null ||
            MathTextbookUnits.values[unit]!.dimension !=
                MathTextbookUnits.values[toUnit]!.dimension ||
            unit == toUnit)) {
      throw const FormatException('换算巩固须选择同量纲的两个不同单位');
    }
    if (unit.isNotEmpty && !MathTextbookUnits.values.containsKey(unit) ||
        toUnit.isNotEmpty && !MathTextbookUnits.values.containsKey(toUnit)) {
      throw const FormatException('巩固单位无效');
    }
    final geometry = !const [
      MathTextbookPracticeKind.engine,
      MathTextbookPracticeKind.parentTask,
      MathTextbookPracticeKind.unitConversion,
      MathTextbookPracticeKind.dataTable,
    ].contains(kind);
    if (geometry && unit.isNotEmpty) {
      final power =
          const [
            MathTextbookPracticeKind.cuboidVolume,
            MathTextbookPracticeKind.cubeVolume,
            MathTextbookPracticeKind.cylinderVolume,
          ].contains(kind)
          ? '³'
          : const [
              MathTextbookPracticeKind.rectanglePerimeter,
              MathTextbookPracticeKind.circlePerimeter,
            ].contains(kind)
          ? ''
          : '²';
      if (MathTextbookUnits.values[unit]?.dimension != 'length' ||
          !MathTextbookUnits.values.containsKey('$unit$power')) {
        throw const FormatException('图形计算须使用已支持的长度单位及其面积或体积单位');
      }
    }
    if (kind == MathTextbookPracticeKind.dataTable &&
        !const ['total', 'mean', 'max', 'difference'].contains(task)) {
      throw const FormatException('统计巩固方式不支持');
    }
    final negative = _boolean(raw['allowNegative'] ?? false, '负数');
    final brackets = _boolean(raw['allowBrackets'] ?? false, '括号');
    final mode = raw['mode'] == null
        ? null
        : _enum(ProblemMode.values, raw['mode'], '巩固题型');
    if (kind == MathTextbookPracticeKind.engine &&
        (minimum < 0 && !negative ||
            mode == ProblemMode.withBrackets && !brackets)) {
      throw const FormatException('数值范围或题型与负数、括号选项不一致');
    }
    if (kind != MathTextbookPracticeKind.engine &&
        kind != MathTextbookPracticeKind.parentTask &&
        (minimum < 1 || maximum > 100)) {
      throw const FormatException('计量、图形和统计巩固的给定数值范围须为 1～100');
    }
    final pi = _string(raw['pi'] ?? '3.14', '圆周率', max: 32);
    final piValue = MathEngine.parseAnswer(pi);
    if (piValue == null || piValue.asDouble < 3 || piValue.asDouble > 4) {
      throw const FormatException('请填写本课使用的圆周率');
    }
    if (ops.isEmpty && kind == MathTextbookPracticeKind.engine) {
      throw const FormatException('巩固运算不能为空');
    }
    return MathTextbookPracticePlan(
      id: _identifier(raw['id']),
      knowledgePointId: _identifier(raw['knowledgePointId']),
      title: _string(raw['title'], '巩固名称', max: 200),
      kind: kind,
      skillId: skill,
      count: _integer(raw['count'] ?? 5, '巩固题数', min: 1, max: 30),
      minOperand: minimum,
      maxOperand: maximum,
      maxResult: _integer(
        raw['maxResult'] ?? 40,
        '结果上限',
        min: 1,
        max: 1000000000,
      ),
      operators: ops,
      mode: mode,
      allowCarry: _boolean(raw['allowCarry'] ?? true, '进位'),
      allowBorrow: _boolean(raw['allowBorrow'] ?? true, '退位'),
      allowRemainder: _boolean(raw['allowRemainder'] ?? false, '余数'),
      allowBrackets: brackets,
      allowNegative: negative,
      decimalPlaces: _integer(raw['decimalPlaces'] ?? 0, '小数位数', max: 4),
      maxDenominator: _integer(
        raw['maxDenominator'] ?? 1,
        '分母上限',
        min: 1,
        max: 100,
      ),
      unit: unit,
      toUnit: toUnit,
      pi: pi,
      task: task,
    );
  }
}

class MathTextbookLearning {
  MathTextbookLearning({
    this.unitTitle = '',
    required List<MathTextbookKnowledgePoint> knowledgePoints,
    required List<MathTextbookExercise> exercises,
    required List<MathTextbookPracticePlan> practicePlans,
    this.coverageConfirmed = false,
    this.noExercises = false,
  }) : knowledgePoints = List.unmodifiable(knowledgePoints),
       exercises = List.unmodifiable(exercises),
       practicePlans = List.unmodifiable(practicePlans);
  final String unitTitle;
  final List<MathTextbookKnowledgePoint> knowledgePoints;
  final List<MathTextbookExercise> exercises;
  final List<MathTextbookPracticePlan> practicePlans;
  final bool coverageConfirmed, noExercises;
  Map<String, dynamic> toJson() => {
    'unitTitle': unitTitle,
    'knowledgePoints': knowledgePoints.map((k) => k.toJson()).toList(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'practicePlans': practicePlans.map((p) => p.toJson()).toList(),
    'coverageConfirmed': coverageConfirmed,
    'noExercises': noExercises,
  };
  factory MathTextbookLearning.fromJson(Object? value) {
    final raw = _object(value, '课时学习配置');
    final knowledge = _list(
      raw['knowledgePoints'],
      '知识点',
      max: 100,
    ).map(MathTextbookKnowledgePoint.fromJson).toList();
    final exercises = _list(
      raw['exercises'],
      '题组',
      max: 1000,
    ).map(MathTextbookExercise.fromJson).toList();
    final plans = _list(
      raw['practicePlans'],
      '巩固计划',
      max: 100,
    ).map(MathTextbookPracticePlan.fromJson).toList();
    if (knowledge.map((k) => k.id).toSet().length != knowledge.length ||
        exercises.map((e) => e.id).toSet().length != exercises.length ||
        plans.map((p) => p.id).toSet().length != plans.length) {
      throw const FormatException('知识点、题目或计划编号重复');
    }
    final ids = knowledge.map((k) => k.id).toSet();
    if (plans.any((p) => !ids.contains(p.knowledgePointId)) ||
        exercises.any(
          (e) => e.knowledgePointIds.any((k) => !ids.contains(k)),
        )) {
      throw const FormatException('学习配置引用了不存在的知识点');
    }
    final noExercises = _boolean(raw['noExercises'] ?? false, '本课无独立习题');
    if (noExercises && exercises.isNotEmpty) {
      throw const FormatException('有原书题目时不能声明无独立习题');
    }
    return MathTextbookLearning(
      unitTitle: _string(raw['unitTitle'] ?? '', '单元名称', max: 200, empty: true),
      knowledgePoints: knowledge,
      exercises: exercises,
      practicePlans: plans,
      coverageConfirmed: _boolean(raw['coverageConfirmed'] ?? false, '内容覆盖确认'),
      noExercises: noExercises,
    );
  }
  void matchBlocks(List<MathTextbookBlock> blocks) {
    final ids = blocks.map((b) => b.id).toSet();
    if (knowledgePoints.any((k) => k.blockIds.any((id) => !ids.contains(id))) ||
        exercises.any((e) => e.blockIds.any((id) => !ids.contains(id)))) {
      throw const FormatException('学习配置引用了不存在的原书内容块');
    }
  }

  void checkReady() {
    if (!coverageConfirmed ||
        knowledgePoints.isEmpty ||
        knowledgePoints.any(
          (k) =>
              k.summary.trim().isEmpty ||
              !practicePlans.any((p) => p.knowledgePointId == k.id),
        ) ||
        exercises.isEmpty && !noExercises) {
      throw const FormatException('请补齐知识要点、原书题目和巩固，并确认本课覆盖后再开启自动练习');
    }
  }
}

T _enum<T extends Enum>(List<T> values, Object? name, String label) {
  final value = values.where((v) => v.name == name).firstOrNull;
  if (value == null) throw FormatException('$label无效');
  return value;
}

bool _boolean(Object? value, String label) {
  if (value is! bool) throw FormatException('$label须为布尔值');
  return value;
}

List<String> _strings(Object? value, String label, int max, int length) =>
    _list(
      value,
      label,
      max: max,
    ).map((v) => _string(v, label, max: length)).toList();
