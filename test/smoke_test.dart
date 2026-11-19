// test/smoke_test.dart
//
// Phase 0 冒烟测试：确保冷启动准备完成后直接进入首页或首启引导。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app_bootstrap.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/shell/main_shell.dart';
import 'package:poemath/features/shell/onboarding_page.dart';

import 'helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForWidgetTesting();
  });

  testWidgets('冷启动准备页展示水墨启动图，完成后直接进入首页', (tester) async {
    final coreGate = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () => coreGate.future,
          optionalInitializer: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.image(const AssetImage('assets/images/splash_art.png')),
      findsOneWidget,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      ColorTokens.startupPaper,
    );
    expect(
      find.image(const AssetImage('assets/icons/app_icon.png')),
      findsNothing,
    );

    coreGate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);

    // 消耗 MainShell IndexedStack 中所有 tab 页面的
    // flutter_animate 入场动画计时器
    await tester.pump(const Duration(seconds: 3));

    // 排空 Hive 写链，否则 tearDown 的 Hive.close() 在 fake 时钟下永不返回。
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('未完成引导时，准备完成后直接进入引导页', (tester) async {
    await tester.runAsync(() => SettingsRepository().setHasOnboarded(false));

    await tester.pumpWidget(
      ProviderScope(
        child: AppBootstrap(
          coreInitializer: () async {},
          optionalInitializer: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    expect(find.text('正在准备韵算…'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await drainHiveWritesForTesting(tester);
  });
}
