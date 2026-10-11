// test/features/assistant/assistant_enabled_provider_test.dart
//
// AI 助手开关 Provider 单元测试：
//   - 默认关闭（无存储值 → false）；
//   - setEnabled 更新状态并持久化到 Hive settings box；
//   - 重建 container 时从 Hive 读回持久化值。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/features/assistant/assistant_enabled_provider.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('默认关闭：无存储值时为 false', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(assistantEnabledProvider), isFalse);
  });

  test('setEnabled(true) 更新状态并持久化到 Hive', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(assistantEnabledProvider.notifier).setEnabled(true);
    expect(container.read(assistantEnabledProvider), isTrue);

    // listenSelf 经 Zone.root 调度写入，放行微任务后断言落盘。
    await Future<void>.delayed(Duration.zero);
    expect(
      HiveBoxes.settings.get(AssistantEnabledNotifier.storageKey),
      isTrue,
    );
  });

  test('重建后从 Hive 读回持久化的开启值', () {
    HiveBoxes.settings.put(AssistantEnabledNotifier.storageKey, true);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(assistantEnabledProvider), isTrue);
  });
}
