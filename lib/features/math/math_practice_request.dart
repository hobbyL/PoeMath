import 'package:poemath/math_engine/math_engine_api.dart';

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
  });

  final int grade;
  final String semester;
  final int count;
  final DifficultyLevel difficulty;
  final ProblemMode? mode;
  final String? skillId;
  final bool verticalProcessOnly;

  Map<String, dynamic> toJson() => {
        'grade': grade,
        'semester': semester,
        'count': count,
        'difficulty': difficulty.name,
        'mode': mode?.name,
        'skillId': skillId,
        'verticalProcessOnly': verticalProcessOnly,
      };

  factory MathPracticeRequest.fromJson(Map<String, dynamic> json) {
    final grade = json['grade'] as int;
    final semester = json['semester'] as String;
    final count = json['count'] as int;
    if (grade < 1 ||
        grade > 6 ||
        !const ['上', '下'].contains(semester) ||
        count < 1 ||
        count > 100) {
      throw const FormatException('练习参数无效');
    }
    return MathPracticeRequest(
      grade: grade,
      semester: semester,
      count: count,
      difficulty: DifficultyLevel.values.byName(json['difficulty'] as String),
      mode: json['mode'] == null
          ? null
          : ProblemMode.values.byName(json['mode'] as String),
      skillId: json['skillId'] as String?,
      verticalProcessOnly: json['verticalProcessOnly'] as bool? ?? false,
    );
  }
}
