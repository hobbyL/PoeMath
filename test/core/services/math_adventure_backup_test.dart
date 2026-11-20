import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_adventure_progress.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

class _FailAdventureRestoreOnce extends Fake
    implements Box<MathAdventureProgress> {
  _FailAdventureRestoreOnce(this.box);
  final Box<MathAdventureProgress> box;
  bool fail = true;
  @override
  Iterable<MathAdventureProgress> get values => box.values;
  @override
  Future<int> clear() => box.clear();
  @override
  Future<void> putAll(Map<dynamic, MathAdventureProgress> entries) async {
    await box.putAll(entries);
    if (fail) {
      fail = false;
      throw HiveError('模拟探险写入后失败');
    }
  }
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
  });
  tearDown(tearDownHiveForTesting);
  MathAdventureProgress progress(String profile) => MathAdventureProgress(
    profileId: profile,
    grade: 1,
    semester: '上',
    completedSkillIds: ['addition', 'subtraction'],
    collectedRegionIds: ['arithmetic_forest'],
  );

  test('全部档案往返、旧备份保留、显式空清空与预览', () async {
    final service = BackupService();
    for (final profile in ['default', 'child2']) {
      final p = progress(profile);
      await HiveBoxes.mathAdventureProgress.put(p.key, p);
    }
    final exported = await service.exportToJson();
    expect(service.inspectJson(exported).counts['数学探险路线'], 2);
    await HiveBoxes.mathAdventureProgress.clear();
    await service.restoreFromJson(exported);
    expect(
      HiveBoxes.mathAdventureProgress.values.map((p) => p.toJson()).toList(),
      unorderedEquals([
        progress('default').toJson(),
        progress('child2').toJson(),
      ]),
    );
    final legacy = jsonDecode(exported) as Map<String, dynamic>;
    legacy.remove('mathAdventureProgress');
    await service.restoreFromJson(jsonEncode(legacy));
    expect(HiveBoxes.mathAdventureProgress.length, 2);
    legacy['mathAdventureProgress'] = <dynamic>[];
    await service.restoreFromJson(jsonEncode(legacy));
    expect(HiveBoxes.mathAdventureProgress.isEmpty, isTrue);
  });

  test('坏 ID、重复路线、重复集合和 null 在任何替换前拒绝', () async {
    final service = BackupService();
    final original = progress('default');
    await HiveBoxes.mathAdventureProgress.put(original.key, original);
    final invalidCollections = <Object?>[
      null,
      [original.toJson(), original.toJson()],
      [
        {...original.toJson(), 'profileId': ''},
      ],
      [
        {
          ...original.toJson(),
          'completedSkillIds': ['unknown'],
        },
      ],
      [
        {
          ...original.toJson(),
          'completedSkillIds': ['addition', 'addition'],
        },
      ],
      [
        {
          ...original.toJson(),
          'collectedRegionIds': ['unknown'],
        },
      ],
      [
        {...original.toJson(), 'grade': 7},
      ],
    ];
    for (final bad in invalidCollections) {
      await expectLater(
        service.restoreFromJson(
          jsonEncode({'version': 1, 'mathAdventureProgress': bad}),
        ),
        throwsFormatException,
      );
      expect(
        HiveBoxes.mathAdventureProgress.get(original.key)!.toJson(),
        original.toJson(),
      );
    }
  });

  test('写入新探险数据后恢复失败，补偿完整还原原集合', () async {
    final original = progress('default');
    final box = HiveBoxes.mathAdventureProgress;
    await box.put(original.key, original);
    HiveBoxes.mathAdventureProgress = _FailAdventureRestoreOnce(box);
    try {
      await expectLater(
        BackupService().restoreFromJson(
          jsonEncode({
            'version': 1,
            'mathAdventureProgress': [progress('child2').toJson()],
          }),
        ),
        throwsA(isA<HiveError>()),
      );
    } finally {
      HiveBoxes.mathAdventureProgress = box;
    }
    expect(box.values.map((p) => p.toJson()), [original.toJson()]);
    expect(HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0), 0);
  });
}
