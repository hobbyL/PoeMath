// lib/features/shell/onboarding_page.dart
//
// 层级：features/shell
// 职责：新手引导页 — 首次启动时展示3页介绍，完成后标记已引导并进入首页。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = <_OnboardingData>[
    _OnboardingData(
      icon: Icons.auto_stories_rounded,
      title: '读诗',
      subtitle: '小学必背古诗文',
      description: '精选教材古诗词，配合朗读、背诵、测验三步学习法，'
          '搭配科学复习算法，让背诵更高效。',
    ),
    _OnboardingData(
      icon: Icons.calculate_rounded,
      title: '算数',
      subtitle: '口算能力提升',
      description: '多难度分级口算练习，自动归纳错题，'
          '公式卡片收藏，帮助孩子扎实掌握数学基础。',
    ),
    _OnboardingData(
      icon: Icons.emoji_events_rounded,
      title: '成长',
      subtitle: '记录每一步进步',
      description: '打卡激励、星星等级、成就勋章，'
          '让学习像闯关一样有趣，每一次努力都被看见。',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.setHasOnboarded(true);
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 跳过按钮
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finishOnboarding,
                child: Text(
                  '跳过',
                  style: TextStyle(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),

            // 页面内容
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _buildPage(context, _pages[index], index);
                },
              ),
            ),

            // 底部指示器 + 按钮
            Padding(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 页面指示点
                  Row(
                    children: List.generate(_pages.length, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: 300.ms,
                        margin: const EdgeInsets.only(right: SpacingTokens.xs),
                        width: isActive ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary
                                  .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            SpacingTokens.radiusPill,
                          ),
                        ),
                      );
                    }),
                  ),

                  // 下一步 / 开始按钮
                  FilledButton.icon(
                    onPressed: () {
                      if (isLast) {
                        _finishOnboarding();
                      } else {
                        _controller.nextPage(
                          duration: 400.ms,
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                    label: Text(isLast ? '开始使用' : '下一步'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    _OnboardingData data,
    int index,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 图标
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              data.icon,
              size: 56,
              color: theme.colorScheme.primary,
            ),
          )
              .animate(
                key: ValueKey('onboarding_icon_$index'),
              )
              .scaleXY(
                begin: 0.5,
                end: 1.0,
                duration: 500.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 400.ms),

          const SizedBox(height: SpacingTokens.xl),

          // 标题
          Text(
            data.title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          )
              .animate(
                key: ValueKey('onboarding_title_$index'),
              )
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideY(begin: 0.3, end: 0, duration: 400.ms),

          const SizedBox(height: SpacingTokens.sm),

          // 副标题
          Text(
            data.subtitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          )
              .animate(
                key: ValueKey('onboarding_subtitle_$index'),
              )
              .fadeIn(delay: 300.ms, duration: 400.ms),

          const SizedBox(height: SpacingTokens.lg),

          // 描述
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.8,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          )
              .animate(
                key: ValueKey('onboarding_desc_$index'),
              )
              .fadeIn(delay: 400.ms, duration: 400.ms),

          const SizedBox(height: SpacingTokens.xl),

          // 品牌 slogan（仅首页）
          if (index == 0)
            Text(
              AppConstants.slogan,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ).animate().fadeIn(delay: 600.ms, duration: 600.ms),
        ],
      ),
    );
  }
}

class _OnboardingData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;

  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
  });
}
