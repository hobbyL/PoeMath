import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('次数持久化、冷读取、自动与旧坏值回落', () async {
    final repository = SettingsRepository();
    expect(repository.mathOperationCounts, isNull);
    await repository.setMathOperationCounts(OperationCounts([3, 2]));
    expect(HiveBoxes.settings.get('math_operation_counts'), '2,3');
    expect(SettingsRepository().mathOperationCounts?.values, [2, 3]);
    await repository.setMathOperationCounts(null);
    expect(SettingsRepository().mathOperationCounts, isNull);
    for (final bad in <Object>[
      '',
      '0',
      '2,2',
      '1,4',
      [2, 3],
    ]) {
      await HiveBoxes.settings.put('math_operation_counts', bad);
      expect(SettingsRepository().mathOperationCounts, isNull);
    }
  });
}
