// test/features/assistant/assistant_bubble_gate_test.dart
//
// 悬浮气泡门控（端到端）：MainShell 据 assistantEnabledProvider 决定是否
// 挂载 DraggableAssistantBubble。默认关闭不显示；开启后出现；再关闭消失。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/features/assistant/assistant_enabled_provider.dart';
import 'package:poemath/features/assistant/widgets/draggable_assistant_bubble.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

/// 等待 splash 结束并消耗入场动画计时器（与 main_shell_test 同构）。
Future<void> _pumpPastSplashAndAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('默认关闭不挂载气泡；开启后出现、关闭后消失', (tester) async {
    final container = ProviderContainer(overrides: [staticDayKeyOverride()]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );
    await _pumpPastSplashAndAnimations(tester);

    // 默认关闭 → 无气泡。
    expect(find.byType(DraggableAssistantBubble), findsNothing);

    // 开启 → 气泡出现。
    container.read(assistantEnabledProvider.notifier).setEnabled(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(DraggableAssistantBubble), findsOneWidget);

    // 关闭 → 气泡消失。
    container.read(assistantEnabledProvider.notifier).setEnabled(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(DraggableAssistantBubble), findsNothing);
  });
}
