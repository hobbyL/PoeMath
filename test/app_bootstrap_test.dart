import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/app_bootstrap.dart';

void main() {
  testWidgets('核心存储初始化失败后可重试并进入应用', (tester) async {
    var coreAttempts = 0;
    var optionalAttempts = 0;

    await tester.pumpWidget(
      AppBootstrap(
        coreInitializer: () async {
          coreAttempts++;
          if (coreAttempts == 1) {
            throw StateError('storage unavailable');
          }
        },
        optionalInitializer: () async {
          optionalAttempts++;
        },
        readyChild: const MaterialApp(
          home: Scaffold(body: Text('应用已启动')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('启动失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(coreAttempts, 1);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(find.text('应用已启动'), findsOneWidget);
    expect(coreAttempts, 2);
    expect(optionalAttempts, 1);
  });

  testWidgets('可选服务初始化失败不阻断应用启动', (tester) async {
    var optionalAttempts = 0;

    await tester.pumpWidget(
      AppBootstrap(
        coreInitializer: () async {},
        optionalInitializer: () async {
          optionalAttempts++;
          throw StateError('notifications unavailable');
        },
        readyChild: const MaterialApp(
          home: Scaffold(body: Text('应用已启动')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('应用已启动'), findsOneWidget);
    expect(find.text('启动失败'), findsNothing);
    expect(optionalAttempts, 1);
    expect(tester.takeException(), isNull);
  });
}
