import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/widgets/learning_background_fields.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/repositories/poem_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('学习背景重建后统一，临时跨年级浏览不写回', () async {
    final settings = SettingsRepository();
    await settings.setLearningBackground(4, '下');
    final first = ProviderContainer();
    expect(first.read(mathGradeProvider), 4);
    expect(first.read(mathSemesterProvider), '下');
    expect(first.read(selectedGradeProvider), 4);
    expect(first.read(selectedSemesterProvider), '下');
    first.read(mathGradeProvider.notifier).state = 2;
    first.read(mathSemesterProvider.notifier).state = '上';
    first.read(selectedGradeProvider.notifier).state = null;
    first.dispose();
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(restarted.read(mathGradeProvider), 4);
    expect(restarted.read(mathSemesterProvider), '下');
    expect(restarted.read(selectedGradeProvider), 4);
    expect(settings.selectedGrade, 4);
    expect(settings.selectedSemester, '下');
  });

  test('旧设置默认可用，非法背景整体拒绝，备份恢复同步默认', () async {
    final settings = SettingsRepository();
    expect(settings.selectedGrade, 1);
    expect(settings.selectedSemester, '上');
    await expectLater(
      settings.setLearningBackground(4, '暑假'),
      throwsArgumentError,
    );
    expect(settings.selectedGrade, 1);
    await settings.setLearningBackground(4, '下');
    final backup = BackupService();
    final exported = await backup.exportToJson();
    final data = jsonDecode(exported) as Map<String, dynamic>;
    expect(
      (data['settings'] as Map<String, dynamic>)['selected_semester'],
      '下',
    );
    await settings.setLearningBackground(2, '上');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(mathGradeProvider), 2);
    await backup.restoreFromJson(exported);
    invalidateAllHiveProviders(container.invalidate);
    expect(container.read(mathGradeProvider), 4);
    expect(container.read(mathSemesterProvider), '下');
    expect(container.read(selectedSemesterProvider), '下');
  });

  test('教材推荐优先当前册次必背，诗词临时学期可清除', () async {
    await SettingsRepository().setLearningBackground(4, '下');
    for (final (id, grade, semester) in [
      ('a', 4, '上'),
      ('b', 4, '下'),
      ('c', 2, '下'),
    ]) {
      await HiveBoxes.poems.put(
        id,
        Poem(
          id: id,
          title: id,
          author: '作者',
          dynasty: '唐',
          content: '春眠不觉晓。',
          pinyin: 'chūn mián bù jué xiǎo',
          layer: 'core',
          grade: grade,
          semester: semester,
          isRequired: true,
        ),
      );
    }
    PoemRepository.resetIndices();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(dailyRecommendedPoemProvider)?.id, 'b');
    expect(container.read(filteredPoemsProvider).map((p) => p.id), ['b']);
    container.read(selectedSemesterProvider.notifier).state = null;
    expect(container.read(filteredPoemsProvider).map((p) => p.id), ['a', 'b']);
  });

  testWidgets('学习背景选择在窄屏大字下可读可操作', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var choice = (1, '上');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: LearningBackgroundFields(
                grade: 1,
                semester: '上',
                onChanged: (g, s) => choice = (g, s),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('4 年级'));
    expect(choice, (4, '上'));
    await tester.ensureVisible(find.text('下学期'));
    await tester.tap(find.text('下学期'));
    expect(choice, (1, '下'));
    expect(tester.takeException(), isNull);
  });
}
