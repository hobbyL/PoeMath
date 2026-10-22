import 'math_problem.dart';
import 'problem_skeleton.dart';

/// 由本地决定的数量关系，不能由模型自由改写。
enum WordProblemRelation {
  merge,
  increase,
  decrease,
  more,
  less,
  difference,
  equalGroups,
  equalShare,
  groupCount,
  sequential,
  groupedChange,
  sharedChange,
  restoreInitial,
  findAdded,
  inverseMore,
  inverseLess,
}

enum WordProblemSource { aiScene, localTemplate }

enum WordProblemValidationStatus { verified, needsReview, rejected }

class WordProblemIssue {
  const WordProblemIssue(this.code, this.message, {this.field = ''});

  final String code;
  final String message;
  final String field;
}

class WordProblemValidationResult {
  WordProblemValidationResult(
    this.status, [
    List<WordProblemIssue> issues = const [],
  ]) : issues = List.unmodifiable(issues);

  final WordProblemValidationStatus status;
  final List<WordProblemIssue> issues;
  bool get canSave => status == WordProblemValidationStatus.verified;
}

/// 数量用ID绑定；数值相等不代表两个量具有相同角色。
class WordProblemQuantity {
  const WordProblemQuantity({
    required this.id,
    required this.role,
    required this.entity,
    required this.unit,
    required this.value,
    this.perUnit,
    this.known = true,
  });

  final String id;
  final String role;
  final String entity;
  final String unit;
  final String? perUnit;
  final int value;
  final bool known;

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role,
        'entity': entity,
        'unit': unit,
        'perUnit': perUnit,
        'value': value,
        'known': known,
      };
}

class WordProblemPlanStep {
  WordProblemPlanStep({
    required List<String> inputs,
    required this.output,
    required this.operator,
    required this.value,
  }) : inputs = List.unmodifiable(inputs);

  final List<String> inputs;
  final String output;
  final Operator operator;
  final int value;

  Map<String, Object?> toJson() => {
        'inputs': inputs,
        'output': output,
        'operator': operator.symbol,
        'value': value,
      };
}

/// 本地题意计划。每个关系对应审核过的条件、所求和解题步骤。
/// 数量与步骤由关系派生，外部不能提供另一套自报正确的推导。
class WordProblemPlan {
  WordProblemPlan({
    required ProblemSkeleton skeleton,
    required this.relation,
    required this.sceneId,
    this.variantId = 'standard',
    int? version,
  })  : version = version ??
            switch (relation) {
              WordProblemRelation.restoreInitial ||
              WordProblemRelation.findAdded ||
              WordProblemRelation.inverseMore ||
              WordProblemRelation.inverseLess =>
                2,
              _ => 1,
            },
        skeleton = ProblemSkeleton(
          operands: List.unmodifiable(skeleton.operands),
          operators: List.unmodifiable(skeleton.operators),
          answer: skeleton.answer,
          unitHint: skeleton.unitHint,
          difficulty: skeleton.difficulty,
        );

  final ProblemSkeleton skeleton;
  final WordProblemRelation relation;
  final String sceneId;
  final String variantId;
  final int version;
  String get templateId => '${relation.name}:$variantId';
  String get targetQuantityId => 'target';
}
