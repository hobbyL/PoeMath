import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/presets/difficulty_adjuster.dart';

void main() {
  test('四区唯一覆盖全部技能，低年级收藏没有不可达区域', () {
    final skills = MathAdventureRegion.values.expand((r) => r.skills).toList();
    expect(skills.length, MathSkill.values.length);
    expect(skills.toSet(), MathSkill.values.toSet());
    expect(MathAdventureCatalog.collectible(1, '上'), {
      MathAdventureRegion.forest,
    });
  });
  for (final preset in GradePresets.all) {
    for (final difficulty in DifficultyLevel.values) {
      test('${preset.label}/${difficulty.name} 确定性能力与真实专项批量一致', () {
        final supported = MathEngine.supportedSkills(
          grade: preset.grade,
          semester: preset.semester,
          difficulty: difficulty,
        );
        final config = DifficultyAdjuster.adjust(preset, difficulty);
        for (final skill in MathSkill.values) {
          if (!supported.contains(skill)) {
            expect(
              () => MathEngine.generate(
                grade: preset.grade,
                semester: preset.semester,
                difficulty: difficulty,
                skillId: skill.id,
                random: Random(37),
              ),
              throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
            );
            continue;
          }
          for (final count in [1, 10, 100]) {
            final batch = MathEngine.generateBatch(
              grade: preset.grade,
              semester: preset.semester,
              difficulty: difficulty,
              skillId: skill.id,
              count: count,
              random: Random(count + 29),
            );
            expect(batch, hasLength(count));
            for (final p in batch) {
              expect(p.skillId, skill.id);
              expect(p.mode, isNot(ProblemMode.vertical));
              expect(ConstraintChecker.check(p, config), isNull);
              if (skill == MathSkill.equation) {
                expect(p.mode, ProblemMode.findMissing);
              }
            }
          }
        }
      });
    }
  }
}
