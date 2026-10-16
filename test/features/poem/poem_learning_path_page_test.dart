import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/poem_curriculum.dart';
import 'package:poemath/features/poem/poem_learning_path_page.dart';

import '../../helpers/hive_test_helper.dart';

Poem entry(String id,
        {bool required = true,
        String semester = '下',
        int grade = 4,
        String unit = '课文1',}) =>
    Poem(
      id: id,
      title: id,
      author: '李白',
      dynasty: '唐',
      content: '诗句',
      pinyin: '',
      layer: 'core',
      grade: grade,
      semester: semester,
      textbookUnit: unit,
      isRequired: required,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('必背按实际册次筛选并按课文数字排序，拓展不进入必背分母', () {
    final result = requiredTextbookPoems([
      entry('ten', unit: '课文10'),
      entry('two', unit: '课文2'),
      entry('extend', required: false),
      entry('other', semester: '上'),
    ], 4, '下',);
    expect(result.map((poem) => poem.id).toList(), ['two', 'ten']);
  });

  testWidgets('高年级直接进入当前册必背，拓展不计进度；窄屏大字号无溢出', (tester) async {
    await tester.runAsync(() async {
      await SettingsRepository().setLearningBackground(4, '下');
      for (final poem in [
        entry('本册必背'),
        entry('本册拓展', required: false),
        entry('其他学期', semester: '上'),
        entry('低年级', grade: 1),
      ]) {
        await HiveBoxes.poems.put(poem.id, poem);
      }
      await PoemProgressRepository().save(PoemProgress(
          poemId: '本册拓展',
          profileId: 'default',
          status: LearningStatus.mastered,),);
    });
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,),
      home: const PoemLearningPathPage(),
    ),),);
    await tester.pumpAndSettle();
    expect(find.text('本册必背 0/1 首已学 · 0 首已掌握'), findsOneWidget);
    expect(find.text('本册必背'), findsWidgets);
    expect(find.text('其他学期'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 年级').last);
    await tester.pumpAndSettle();
    expect(SettingsRepository().selectedGrade, 4);
    expect(SettingsRepository().selectedSemester, '下');
    expect(tester.takeException(), isNull);
  });
}
