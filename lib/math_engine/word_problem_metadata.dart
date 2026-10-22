import 'dart:convert';

import 'models/math_problem.dart';
import 'models/problem_skeleton.dart';
import 'models/word_problem_plan.dart';
import 'word_problem_plan_rules.dart';
import 'word_problem_renderer.dart';

/// 版本化计划快照，保存和恢复都重新核对实际题目。
class WordProblemMetadata {
  WordProblemMetadata({required this.plan, required this.source});

  static const schemaVersion = 1;
  final WordProblemPlan plan;
  final WordProblemSource source;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'planVersion': plan.version,
        'templateVersion': 1,
        'templateId': plan.templateId,
        'relation': plan.relation.name,
        'sceneId': plan.sceneId,
        'variantId': plan.variantId,
        'source': source.name,
        'operands': plan.skeleton.operands,
        'operators': plan.skeleton.operators.map((op) => op.symbol).toList(),
        'answer': plan.skeleton.answer,
        'unit': plan.skeleton.unitHint,
        'difficulty': plan.skeleton.difficulty,
        'targetQuantityId': plan.targetQuantityId,
        'quantities': WordProblemPlanRules.quantities(plan)
            .map((q) => q.toJson())
            .toList(),
        'steps':
            WordProblemPlanRules.steps(plan).map((s) => s.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static WordProblemMetadata? decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] is! int ||
          (decoded['schemaVersion'] as int) < 1) {
        throw const FormatException('题意快照格式无效');
      }
      if ((decoded['schemaVersion'] as int) > schemaVersion ||
          decoded['planVersion'] is int &&
              (decoded['planVersion'] as int) > 2 ||
          decoded['templateVersion'] is int &&
              (decoded['templateVersion'] as int) > 1) {
        return null;
      }
      final numbers = decoded['operands'];
      final symbols = decoded['operators'];
      if (numbers is! List<Object?> ||
          numbers.any((v) => v is! int) ||
          symbols is! List<Object?> ||
          symbols.any((v) => v is! String) ||
          decoded['answer'] is! int ||
          decoded['unit'] is! String ||
          decoded['difficulty'] is! int) {
        throw const FormatException('题意快照数量格式无效');
      }
      final plan = WordProblemPlan(
        skeleton: ProblemSkeleton(
          operands: numbers.cast<int>(),
          operators: symbols
              .map(
                (symbol) =>
                    Operator.values.firstWhere((op) => op.symbol == symbol),
              )
              .toList(),
          answer: decoded['answer'] as int,
          unitHint: decoded['unit'] as String,
          difficulty: decoded['difficulty'] as int,
        ),
        relation: WordProblemRelation.values
            .firstWhere((v) => v.name == decoded['relation']),
        sceneId: decoded['sceneId'] as String,
        variantId: decoded['variantId'] as String,
        version: decoded['planVersion'] as int,
      );
      if (!WordProblemPlanRules.validate(plan).canSave) {
        throw const FormatException('题意快照数量关系无效');
      }
      final metadata = WordProblemMetadata(
        plan: plan,
        source: WordProblemSource.values
            .firstWhere((v) => v.name == decoded['source']),
      );
      if (jsonEncode(_canonical(decoded)) !=
          jsonEncode(_canonical(metadata.toJson()))) {
        throw const FormatException('题意快照与本地数量关系不一致');
      }
      return metadata;
    } on FormatException {
      rethrow;
    } on TypeError {
      throw const FormatException('题意快照字段类型无效');
    } on StateError {
      throw const FormatException('题意快照包含未知关系或运算');
    }
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  bool matches({
    required String text,
    required String explanation,
    required List<int> operands,
    required List<String> operators,
    required int answer,
    required String unit,
    required int difficulty,
  }) {
    final rendered = WordProblemRenderer.render(plan);
    return rendered.text == text &&
        rendered.explanation == explanation &&
        jsonEncode(operands) == jsonEncode(plan.skeleton.operands) &&
        jsonEncode(operators) ==
            jsonEncode(
              plan.skeleton.operators.map((op) => op.symbol).toList(),
            ) &&
        answer == plan.skeleton.answer &&
        unit == plan.skeleton.unitHint &&
        difficulty == plan.skeleton.difficulty;
  }

  bool matchesContext({
    required int grade,
    required String semester,
    required String topic,
  }) =>
      WordProblemPlanRules.validateContext(
        plan,
        grade: grade,
        semester: semester,
        topic: topic,
      ).canSave;
}
