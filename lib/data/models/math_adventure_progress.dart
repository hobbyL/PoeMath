import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/math_engine/models/math_skill.dart';

/// 不可变的整条路线快照；完成与收藏同帧写入，失败不污染内存旧值。
class MathAdventureProgress {
  MathAdventureProgress({
    required this.profileId,
    required this.grade,
    required this.semester,
    Iterable<String> completedSkillIds = const [],
    Iterable<String> collectedRegionIds = const [],
  }) : completedSkillIds = Set.unmodifiable(completedSkillIds),
       collectedRegionIds = Set.unmodifiable(collectedRegionIds);

  final String profileId, semester;
  final int grade;
  final Set<String> completedSkillIds, collectedRegionIds;
  static String keyFor(String profileId, int grade, String semester) =>
      jsonEncode([profileId, grade, semester]);
  String get key => keyFor(profileId, grade, semester);

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'grade': grade,
    'semester': semester,
    'completedSkillIds': completedSkillIds.toList()..sort(),
    'collectedRegionIds': collectedRegionIds.toList()..sort(),
  };

  factory MathAdventureProgress.fromJson(Map<String, dynamic> json) {
    final profile = json['profileId'],
        grade = json['grade'],
        semester = json['semester'];
    if (profile is! String ||
        profile.trim().isEmpty ||
        profile.length > 200 ||
        grade is! int ||
        grade < 1 ||
        grade > 6 ||
        !['上', '下'].contains(semester)) {
      throw const FormatException('探险档案或册次无效');
    }
    Set<String> ids(String key, bool Function(String) known, int limit) {
      final raw = json[key];
      if (raw is! List ||
          raw.length > limit ||
          raw.any((id) => id is! String || !known(id))) {
        throw FormatException('探险 $key 无效');
      }
      final result = raw.cast<String>().toSet();
      if (result.length != raw.length) throw FormatException('探险 $key 重复');
      return result;
    }

    return MathAdventureProgress(
      profileId: profile,
      grade: grade,
      semester: semester as String,
      completedSkillIds: ids(
        'completedSkillIds',
        (id) => MathSkill.fromId(id) != null,
        16,
      ),
      collectedRegionIds: ids(
        'collectedRegionIds',
        (id) => MathAdventureRegion.fromId(id) != null,
        4,
      ),
    );
  }
}

/// 固定字段 0–4，后续字段只追加并给出读取默认值。
class MathAdventureProgressAdapter extends TypeAdapter<MathAdventureProgress> {
  @override
  final int typeId = 22;
  @override
  MathAdventureProgress read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = {
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return MathAdventureProgress.fromJson({
      'profileId': fields[0],
      'grade': fields[1],
      'semester': fields[2],
      'completedSkillIds': fields[3] ?? <String>[],
      'collectedRegionIds': fields[4] ?? <String>[],
    });
  }

  @override
  void write(BinaryWriter writer, MathAdventureProgress obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.profileId)
      ..writeByte(1)
      ..write(obj.grade)
      ..writeByte(2)
      ..write(obj.semester)
      ..writeByte(3)
      ..write(obj.completedSkillIds.toList())
      ..writeByte(4)
      ..write(obj.collectedRegionIds.toList());
  }
}
