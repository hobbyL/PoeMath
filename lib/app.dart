// lib/app.dart
//
// 层级：应用根 Widget
// 职责：装配 MaterialApp.router；消费主题、路由、locale。
// 依赖：Riverpod / go_router / theme_providers / app_router。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/theme/theme_providers.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final light = ref.watch(lightThemeProvider);
    final dark = ref.watch(darkThemeProvider);
    final mode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
