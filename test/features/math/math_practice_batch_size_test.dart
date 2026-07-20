import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('同类新题临时覆盖只消费一次且不污染持久设置', () async {
    await HiveBoxes.settings.put('math_batch_size', 20);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final override = container.read(mathBatchSizeOverrideProvider.notifier);
    final settings = container.read(settingsRepositoryProvider);

    override.setNext(5);

    expect(override.consumeOr(settings.mathBatchSize), 5);
    expect(container.read(mathBatchSizeOverrideProvider), isNull);
    expect(override.consumeOr(settings.mathBatchSize), 20);
    expect(settings.mathBatchSize, 20);
  });
}
