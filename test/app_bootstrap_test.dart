import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/app_bootstrap.dart';

void main() {
  testWidgets('核心存储初始化失败后可重试并进入应用', (tester) async {
    var coreAttempts = 0;
    var optionalAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () async {
            coreAttempts++;
            if (coreAttempts == 1) {
              throw StateError('storage unavailable');
            }
          },
          optionalInitializer: () async {
            optionalAttempts++;
          },
          dataInitializer: (_) async => false,
          indexBuilder: () async {},
          readyChild: const MaterialApp(home: Scaffold(body: Text('应用已启动'))),
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
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () async {},
          optionalInitializer: () async {
            optionalAttempts++;
            throw StateError('notifications unavailable');
          },
          dataInitializer: (_) async => false,
          indexBuilder: () async {},
          readyChild: const MaterialApp(home: Scaffold(body: Text('应用已启动'))),
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

  testWidgets('静态资料导入失败后重试并进入应用', (tester) async {
    var coreAttempts = 0;
    var optionalAttempts = 0;
    var dataAttempts = 0;
    var indexAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () async {
            coreAttempts++;
          },
          optionalInitializer: () async {
            optionalAttempts++;
          },
          dataInitializer: (_) async {
            dataAttempts++;
            if (dataAttempts == 1) throw StateError('asset unavailable');
            return false;
          },
          indexBuilder: () async {
            indexAttempts++;
          },
          readyChild: const MaterialApp(home: Scaffold(body: Text('应用已启动'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('学习资料加载失败，请重试。'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('应用已启动'), findsOneWidget);
    expect(dataAttempts, 2);
    expect(indexAttempts, 1);
    expect(coreAttempts, 1);
    expect(optionalAttempts, 1);
  });

  testWidgets('索引构建失败后重试数据导入和索引', (tester) async {
    var dataAttempts = 0;
    var indexAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () async {},
          optionalInitializer: () async {},
          dataInitializer: (_) async {
            dataAttempts++;
            return false;
          },
          indexBuilder: () async {
            indexAttempts++;
            if (indexAttempts == 1) throw StateError('index unavailable');
          },
          readyChild: const MaterialApp(home: Scaffold(body: Text('应用已启动'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('学习资料加载失败，请重试。'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('应用已启动'), findsOneWidget);
    expect(dataAttempts, 2);
    expect(indexAttempts, 2);
  });

  testWidgets('资料导入与索引均完成后才离开准备页', (tester) async {
    final dataGate = Completer<bool>();
    final indexGate = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () async {},
          optionalInitializer: () async {},
          dataInitializer: (onProgress) {
            onProgress(0.5);
            return dataGate.future;
          },
          indexBuilder: () => indexGate.future,
          readyChild: const MaterialApp(home: Text('应用已启动')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在整理古诗…'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
    expect(find.text('应用已启动'), findsNothing);

    dataGate.complete(true);
    await tester.pump();
    expect(find.text('正在整理诗词索引…'), findsOneWidget);
    expect(find.text('应用已启动'), findsNothing);

    indexGate.complete();
    await tester.pump();
    expect(find.text('应用已启动'), findsOneWidget);
  });

  testWidgets('准备页卸载后，迟到的导入结果不再启动索引', (tester) async {
    final dataGate = Completer<bool>();
    var indexAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () async {},
          optionalInitializer: () async {},
          dataInitializer: (_) => dataGate.future,
          indexBuilder: () async {
            indexAttempts++;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    dataGate.complete(true);
    await tester.pump();

    expect(indexAttempts, 0);
    expect(tester.takeException(), isNull);
  });
}
