import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_adventure_progress.dart';
import 'package:poemath/data/repositories/math_adventure_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

class _ControlledProgressBox extends Fake
    implements Box<MathAdventureProgress> {
  _ControlledProgressBox(this.box);
  final Box<MathAdventureProgress> box;
  bool fail = false;
  Completer<void>? gate;
  final entered = Completer<void>();
  int writes = 0;
  @override
  MathAdventureProgress? get(
    dynamic key, {
    MathAdventureProgress? defaultValue,
  }) => box.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, MathAdventureProgress value) async {
    writes++;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (fail) throw HiveError('模拟进度落盘失败');
    await box.put(key, value);
  }
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });
  Future<MathAdventureCompletion> complete(
    MathAdventureRepository repo,
    String skill, {
    int grade = 1,
    String semester = '上',
    DifficultyLevel difficulty = DifficultyLevel.medium,
  }) => repo.complete(
    node: MathAdventureNode(grade: grade, semester: semester, skillId: skill),
    difficulty: difficulty,
    ensureCurrent: repo.assertCurrent,
  );

  test('开放顺序、同路线并发并集、奖励只发一次与真实重开', () async {
    final repo = MathAdventureRepository();
    expect(
      () => repo.assertCanStart(
        const MathAdventureNode(
          grade: 1,
          semester: '上',
          skillId: 'subtraction',
        ),
        DifficultyLevel.medium,
      ),
      throwsStateError,
    );
    await Future.wait([
      complete(repo, 'addition'),
      complete(repo, 'subtraction'),
    ]);
    final progress = repo.read(1, '上');
    expect(progress.completedSkillIds, {'addition', 'subtraction'});
    expect(progress.collectedRegionIds, {'arithmetic_forest'});
    expect((await complete(repo, 'addition')).newRegions, isEmpty);
    final path = HiveBoxes.mathAdventureProgress.path!;
    final name = HiveBoxes.mathAdventureProgress.name;
    await HiveBoxes.mathAdventureProgress.close();
    HiveBoxes.mathAdventureProgress = await Hive.openBox<MathAdventureProgress>(
      name,
      path: path.substring(0, path.lastIndexOf('/')),
      crashRecovery: false,
    );
    expect(MathAdventureRepository().read(1, '上').toJson(), progress.toJson());
  });
  test('降低难度补齐收藏，提高难度与切册不删除状态', () async {
    final repo = MathAdventureRepository();
    await complete(repo, 'addition', semester: '下');
    await complete(repo, 'subtraction', semester: '下');
    expect(repo.read(1, '下').collectedRegionIds, isEmpty);
    expect((await repo.reconcile(1, '下', DifficultyLevel.easy)).newRegions, {
      'arithmetic_forest',
    });
    expect(
      (await repo.reconcile(1, '下', DifficultyLevel.hard)).newRegions,
      isEmpty,
    );
    expect(repo.read(1, '下').completedSkillIds, {'addition', 'subtraction'});
    expect(repo.read(1, '上').completedSkillIds, isEmpty);
  });
  test('档案切走再切回和恢复 epoch 都使旧实例失效', () async {
    final repo = MathAdventureRepository();
    await complete(repo, 'addition');
    ProfileScope.switchTo('child2');
    expect(MathAdventureRepository().read(1, '上').completedSkillIds, isEmpty);
    await expectLater(complete(repo, 'subtraction'), throwsStateError);
    ProfileScope.reset();
    await expectLater(complete(repo, 'subtraction'), throwsStateError);
    final current = MathAdventureRepository();
    await PracticeDraftRepository.whileRestoring(
      () => PracticeDraftRepository.clearAll(),
    );
    await expectLater(complete(current, 'subtraction'), throwsStateError);
    expect(MathAdventureRepository().read(1, '上').completedSkillIds, {
      'addition',
    });
  });

  test('失败不污染已有集合，重试成功；对账和重玩不重复写入', () async {
    final box = _ControlledProgressBox(HiveBoxes.mathAdventureProgress);
    final repository = MathAdventureRepository(box: box);
    await complete(repository, 'addition');
    final before = repository.read(1, '上');
    box.fail = true;
    await expectLater(
      complete(repository, 'subtraction'),
      throwsA(isA<HiveError>()),
    );
    expect(before.completedSkillIds, {'addition'});
    expect(repository.read(1, '上').collectedRegionIds, isEmpty);
    box.fail = false;
    await complete(repository, 'subtraction');
    final writes = box.writes;
    await complete(repository, 'addition');
    await repository.reconcile(1, '上', DifficultyLevel.medium);
    expect(box.writes, writes);
  });

  test('恢复屏障排空已进入的探险写入，拒绝新写入和旧 epoch', () async {
    final box = _ControlledProgressBox(HiveBoxes.mathAdventureProgress)
      ..gate = Completer<void>();
    final repository = MathAdventureRepository(box: box);
    final pending = complete(repository, 'addition');
    await box.entered.future;
    bool restoreStarted = false;
    final restoring = PracticeDraftRepository.whileRestoring(() async {
      restoreStarted = true;
      expect(HiveBoxes.mathAdventureProgress.values.single.completedSkillIds, {
        'addition',
      });
      await PracticeDraftRepository.clearAll();
    });
    expect(restoreStarted, isFalse);
    await expectLater(complete(repository, 'subtraction'), throwsStateError);
    // guard 完成后恢复屏障已打开，旧页面不会收到可用的结算结果。
    final rejected = expectLater(pending, throwsStateError);
    box.gate!.complete();
    await rejected;
    await restoring;
    expect(restoreStarted, isTrue);
    await expectLater(complete(repository, 'subtraction'), throwsStateError);
  });
}
