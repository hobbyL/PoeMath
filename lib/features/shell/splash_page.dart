// lib/features/shell/splash_page.dart
//
// 层级：features/shell
// 职责：应用启动页。
//       1. 展示品牌"诗算宝" + slogan + 占位 Lottie。
//       2. 执行首次数据导入（DataBootstrap），显示进度条。
//       3. 导入完成后构建诗词索引，然后进入首页。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/hive/bootstrap.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  static const String _lottiePath = 'assets/lottie/splash_placeholder.json';

  double _progress = 0.0;
  String _statusText = '正在启动…';
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    // 执行数据导入（首次启动或数据版本升级）
    final didImport = await DataBootstrap.ensureInitialized(
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _isImporting = true;
          if (progress < 0.3) {
            _statusText = '正在加载诗词数据…';
          } else if (progress < 0.6) {
            _statusText = '正在整理古诗…';
          } else if (progress < 0.8) {
            _statusText = '正在加载作者资料…';
          } else if (progress < 0.95) {
            _statusText = '正在加载数学公式…';
          } else {
            _statusText = '即将完成…';
          }
        });
      },
    );

    // 构建诗词索引
    await ref.read(poemRepositoryProvider).buildIndices();

    if (!mounted) return;

    if (!didImport) {
      // 未导入 → 短暂展示 Splash 后跳转
      await Future<void>.delayed(
        const Duration(milliseconds: AppConstants.splashMinDurationMs),
      );
    }

    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    context.go(AppRoutes.home);
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
              if (_isImporting) ...[
                const SizedBox(height: SpacingTokens.xl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      Text(
                        _statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
