// lib/features/shell/splash_page.dart
//
// 层级：features/shell
// 职责：应用启动页。展示品牌"诗算宝" + slogan + 占位 Lottie（缺失时降级为 loading）。
//       约 300ms 后自动进入首页。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  static const String _lottiePath = 'assets/lottie/splash_placeholder.json';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      const Duration(milliseconds: AppConstants.splashDurationMs),
      _goHome,
    );
  }

  void _goHome() {
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 160,
                height: 160,
                child: Lottie.asset(
                  _lottiePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const _LoadingFallback(),
                ),
              ),
              const SizedBox(height: SpacingTokens.lg),
              Text(
                AppConstants.appName,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                AppConstants.slogan,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lottie 资源缺失时的降级：常规 loading 圈。
class _LoadingFallback extends StatelessWidget {
  const _LoadingFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}
