import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';

/// 一次练习固定使用的参数，与页面浏览筛选、长期偏好独立。
class MathPracticeRequest {
  const MathPracticeRequest({
    required this.grade,
    required this.semester,
    required this.count,
    required this.difficulty,
    this.mode,
    this.skillId,
    this.verticalProcessOnly = false,
    this.adventureProfileId,
    this.operationCounts,
  });

  final int grade;
  final String semester;
  final int count;
  final DifficultyLevel difficulty;
  final ProblemMode? mode;
  final String? skillId;
  final bool verticalProcessOnly;
  final String? adventureProfileId;
  final OperationCounts? operationCounts;
  MathAdventureNode? get adventureNode => adventureProfileId == null
      ? null
      : MathAdventureNode(grade: grade, semester: semester, skillId: skillId!);

  Map<String, dynamic> toJson() => {
    'grade': grade,
    'semester': semester,
    'count': count,
    'difficulty': difficulty.name,
    'mode': mode?.name,
    'skillId': skillId,
    'verticalProcessOnly': verticalProcessOnly,
    if (operationCounts != null) 'operationCounts': operationCounts!.toJson(),
    if (adventureProfileId != null)
      'adventure': {
        'v': 1,
        'profileId': adventureProfileId,
        'scope': adventureNode!.scope,
      },
  };

  factory MathPracticeRequest.fromJson(Map<String, dynamic> json) {
    final grade = json['grade'] as int;
    final semester = json['semester'] as String;
    final count = json['count'] as int;
    final operationCounts = json['operationCounts'] == null
        ? null
        : OperationCounts.fromJson(json['operationCounts']);
    final mode = json['mode'] == null
        ? null
        : ProblemMode.values.byName(json['mode'] as String);
    if (operationCounts != null &&
        (json['skillId'] != null ||
            json['adventure'] != null ||
            json['mode'] == ProblemMode.vertical.name ||
            json['verticalProcessOnly'] == true ||
            operationCounts != operationCounts.forMode(mode))) {
      throw const FormatException('专项练习不能使用普通口算次数偏好');
    }
    if (grade < 1 ||
        grade > 6 ||
        !const ['上', '下'].contains(semester) ||
        count < 1 ||
        count > 100) {
      throw const FormatException('练习参数无效');
    }
    final adventure = json['adventure'];
    String? adventureProfileId;
    if (adventure != null) {
      if (adventure is! Map<String, dynamic> ||
          adventure['v'] != 1 ||
          adventure['profileId'] is! String ||
          (adventure['profileId'] as String).trim().isEmpty ||
          adventure['scope'] is! String ||
          json['mode'] != null ||
          json['verticalProcessOnly'] == true) {
        throw const FormatException('探险练习来源无效');
      }
      final node = MathAdventureNode.fromScope(adventure['scope'] as String);
      if (node.grade != grade ||
          node.semester != semester ||
          node.skillId != json['skillId']) {
        throw const FormatException('探险练习与节点不一致');
      }
      adventureProfileId = adventure['profileId'] as String;
    }
    return MathPracticeRequest(
      grade: grade,
      semester: semester,
      count: count,
      difficulty: DifficultyLevel.values.byName(json['difficulty'] as String),
      mode: mode,
      skillId: json['skillId'] as String?,
      verticalProcessOnly: json['verticalProcessOnly'] as bool? ?? false,
      adventureProfileId: adventureProfileId,
      operationCounts: operationCounts,
    );
  }
}
