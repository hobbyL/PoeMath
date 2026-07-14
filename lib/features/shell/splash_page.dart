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
import 'package:poemath/data/hive/bootstrap.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
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
