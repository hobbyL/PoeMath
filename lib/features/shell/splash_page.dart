// lib/features/shell/splash_page.dart
//
// 层级：features/shell
// 职责：应用启动页。
//       1. 展示品牌"韵算" + slogan + 品牌动画。
//       2. 执行首次数据导入（DataBootstrap），显示进度条。
//       3. 导入完成后构建诗词索引，然后进入首页。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/bootstrap.dart';
import 'package:poemath/data/providers/repository_providers.dart';

typedef SplashDataInitializer = Future<bool> Function(
  BootstrapProgressCallback onProgress,
);
typedef SplashIndexBuilder = Future<void> Function();

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({
    super.key,
    this.dataInitializer,
    this.indexBuilder,
  });

  final SplashDataInitializer? dataInitializer;
  final SplashIndexBuilder? indexBuilder;

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  double _progress = 0.0;
  String _statusText = '正在启动…';
  bool _isImporting = false;
  bool _isInitializing = false;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeData());
  }

  Future<void> _initializeData() async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
      _progress = 0;
      _statusText = '正在启动…';
      _isImporting = false;
    });

    try {
      final didImport = widget.dataInitializer != null
          ? await widget.dataInitializer!(_updateProgress)
          : await DataBootstrap.ensureInitialized(
              onProgress: _updateProgress,
            );

      if (widget.indexBuilder != null) {
        await widget.indexBuilder!();
      } else {
        await ref.read(poemRepositoryProvider).buildIndices();
      }

      if (!didImport) {
        // 未导入 → 短暂展示 Splash 后跳转
        await Future<void>.delayed(
          const Duration(milliseconds: AppConstants.splashMinDurationMs),
        );
      }

      if (!mounted) return;
      _goHome();
    } catch (error) {
      AppLogger.e(
        '静态数据初始化失败',
        tag: 'Startup',
        error: error,
      );
      if (!mounted) return;
      setState(() {
        _initializationError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void _updateProgress(double progress) {
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
  }

  void _goHome() {
    if (!mounted) return;
    // 首次启动 → 引导页，否则直接进首页
    final hasOnboarded =
        ref.read(settingsRepositoryProvider).hasOnboarded;
    if (hasOnboarded) {
      context.go(AppRoutes.home);
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_initializationError != null) {
      return Scaffold(
        body: StartupFailureView(
          message: '学习资料加载失败，请重试。',
          onRetry: _initializeData,
          isRetrying: _isInitializing,
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // 品牌图标动画
              Icon(
                Icons.auto_stories_rounded,
                size: 80,
                color: theme.colorScheme.primary,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 0.9, end: 1.1, duration: 1200.ms)
                  .shimmer(
                    duration: 1800.ms,
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
              const SizedBox(height: SpacingTokens.lg),
              Text(
                AppConstants.appName,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(
                    begin: 0.3,
                    end: 0,
                    duration: 600.ms,
                    curve: Curves.easeOut,
                  ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                AppConstants.slogan,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 600.ms),
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
