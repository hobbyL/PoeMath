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
import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final light = ref.watch(lightThemeProvider);
    final dark = ref.watch(darkThemeProvider);
    final mode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);
    final pageAnimationsEnabled = ref.watch(pageAnimationsEnabledProvider);
    final transitions = pageTransitionsThemeFor(pageAnimationsEnabled);

    return PageAnimationScope(
      enabled: pageAnimationsEnabled,
      child: MaterialApp.router(
        title: AppConstants.appName,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
        // 在主题颜色插值之外切换转场，保存开关后立即使用对应平台动画。
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(pageTransitionsTheme: transitions),
          child: child ?? const SizedBox.shrink(),
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
