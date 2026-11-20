import 'dart:convert';

import 'package:poemath/math_engine/math_engine_api.dart';

enum MathAdventureRegion {
  forest(
    'arithmetic_forest',
    '四则森林',
    '循着萤火，找到林间的小路',
    '晨光叶',
    '一片留住晨光的叶子，记得你在森林里的每一步。',
    [
      MathSkill.addition,
      MathSkill.additionCarry,
      MathSkill.subtraction,
      MathSkill.subtractionBorrow,
      MathSkill.multiplicationTable,
      MathSkill.multiplication,
      MathSkill.division,
      MathSkill.remainderDivision,
    ],
  ),
  mystery(
    'operation_mystery',
    '运算秘境',
    '穿过古树，发现运算的秘密',
    '星纹石',
    '石头上的星纹，藏着你发现的运算秘密。',
    [MathSkill.operationOrder, MathSkill.operationLaw],
  ),
  plain(
    'number_change_plain',
    '数与变化原野',
    '让不同的数，在花海里相遇',
    '风语花',
    '风经过原野时，送来一朵会讲数字故事的花。',
    [
      MathSkill.decimal,
      MathSkill.fraction,
      MathSkill.percentage,
      MathSkill.negative,
    ],
  ),
  highland(
    'quantity_relation_highland',
    '数量关系高地',
    '沿溪流向上，让未知变得清晰',
    '云端羽',
    '从高地带回的轻羽，纪念你找到未知数的时刻。',
    [MathSkill.equation, MathSkill.ratio],
  );

  const MathAdventureRegion(
    this.id,
    this.title,
    this.subtitle,
    this.souvenir,
    this.story,
    this.skills,
  );
  final String id, title, subtitle, souvenir, story;
  final List<MathSkill> skills;
  String get asset => 'assets/images/adventure_$name.jpg';
  static MathAdventureRegion? fromId(String id) =>
      values.where((region) => region.id == id).firstOrNull;
}

/// 可重建的节点身份，难度与题量属于会话快照，不属于节点。
class MathAdventureNode {
  const MathAdventureNode({
    required this.grade,
    required this.semester,
    required this.skillId,
  });
  final int grade;
  final String semester, skillId;
  static const draftKind = 'mathAdventure';
  String get scope => jsonEncode([grade, semester, skillId]);
  MathSkill get skill => MathSkill.fromId(skillId)!;
  String get volumeLabel => '$grade 年级$semester册';
  void validate() {
    if (grade < 1 ||
        grade > 6 ||
        !['上', '下'].contains(semester) ||
        MathSkill.fromId(skillId) == null) {
      throw const FormatException('探险节点无效');
    }
  }

  factory MathAdventureNode.fromScope(String scope) {
    final value = jsonDecode(scope);
    if (value is! List ||
        value.length != 3 ||
        value[0] is! int ||
        value[1] is! String ||
        value[2] is! String) {
      throw const FormatException('探险草稿身份无效');
    }
    final node = MathAdventureNode(
      grade: value[0] as int,
      semester: value[1] as String,
      skillId: value[2] as String,
    );
    node.validate();
    return node;
  }
}

class MathAdventureCatalog {
  const MathAdventureCatalog._();
  static Map<MathAdventureRegion, List<MathSkill>> regions({
    required int grade,
    required String semester,
    required DifficultyLevel difficulty,
  }) {
    final supported = MathEngine.supportedSkills(
      grade: grade,
      semester: semester,
      difficulty: difficulty,
    ).toSet();
    return Map.unmodifiable({
      for (final region in MathAdventureRegion.values)
        if (region.skills.any(supported.contains))
          region: List<MathSkill>.unmodifiable(
            region.skills.where(supported.contains),
          ),
    });
  }

  static List<MathSkill> route({
    required int grade,
    required String semester,
    required DifficultyLevel difficulty,
  }) => regions(
    grade: grade,
    semester: semester,
    difficulty: difficulty,
  ).values.expand((s) => s).toList();

  static Set<MathAdventureRegion> collectible(int grade, String semester) => {
    for (final difficulty in DifficultyLevel.values)
      ...regions(grade: grade, semester: semester, difficulty: difficulty).keys,
  };

  static MathSkill? current(List<MathSkill> route, Set<String> completed) =>
      route.where((skill) => !completed.contains(skill.id)).firstOrNull;
}
