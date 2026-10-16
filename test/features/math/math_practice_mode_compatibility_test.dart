import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final sample in [(4, 'easy'), (1, 'medium')]) {
    testWidgets('历史不兼容模式 ${sample.$1}/${sample.$2} 提示后正常进入练习', (tester) async {
      await tester.runAsync(() async {
        await HiveBoxes.settings.put('math_difficulty', sample.$2);
        await HiveBoxes.settings.put('math_batch_size', 2);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(mathGradeProvider.notifier).state = sample.$1;
      container.read(mathPracticeModeProvider.notifier).state =
          ProblemMode.compare;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MathPracticePage()),),);
      await tester.pump();
      expect(container.read(mathProblemsProvider), hasLength(2));
      expect(container.read(mathPracticeModeProvider), isNull);
      expect(find.text('所选模式不适用于当前年级或难度，已切换为综合练习'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
