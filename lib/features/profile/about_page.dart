// lib/features/profile/about_page.dart
//
// 层级：features/profile
// 职责：关于页面 — 展示应用版本、开发者信息、隐私政策和开源许可。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = _packageInfo != null
        ? 'v${_packageInfo!.version} (${_packageInfo!.buildNumber})'
        : 'v${AppConstants.appVersion}';

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          children: <Widget>[
            const SizedBox(height: SpacingTokens.lg),

            // 品牌 Logo + 名称
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.auto_stories_rounded,
                    size: 72,
                    color: theme.colorScheme.primary,
                  )
                      .animate()
                      .scaleXY(
                        begin: 0.8,
                        end: 1.0,
                        duration: 500.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fadeIn(duration: 400.ms),
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    AppConstants.slogan,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    version,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.xl),

            // 应用介绍
            ColoredCard(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          '应用介绍',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      '韵算是一款专为小学生设计的学习应用，将古诗文背诵和口算练习融合在一起。'
                      '通过科学的复习算法、有趣的成就系统和丰富的动画反馈，'
                      '让孩子在轻松愉快的氛围中学习成长。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 功能信息
            AppTile(
              icon: Icons.history_edu_outlined,
              iconColor: theme.colorScheme.primary,
              title: '诗词学习',
              subtitle: '小学必背古诗文，科学复习记忆法',
            ),
            const SizedBox(height: SpacingTokens.sm),
            AppTile(
              icon: Icons.calculate_outlined,
              iconColor: theme.colorScheme.secondary,
              title: '口算练习',
              subtitle: '多难度分级，错题本自动归纳',
            ),
            const SizedBox(height: SpacingTokens.sm),
            AppTile(
              icon: Icons.emoji_events_outlined,
              iconColor: theme.colorScheme.tertiary,
              title: '成就体系',
              subtitle: '44枚成就勋章，记录成长足迹',
            ),
            const SizedBox(height: SpacingTokens.md),

            // 隐私政策 & 开源许可
            AppTile(
              icon: Icons.privacy_tip_outlined,
              iconColor: theme.colorScheme.primary,
              title: '隐私政策',
              subtitle: '了解我们如何保护您的数据',
              onTap: () => _showPrivacyPolicy(context),
            ),
            const SizedBox(height: SpacingTokens.sm),
            AppTile(
              icon: Icons.description_outlined,
              iconColor: theme.colorScheme.secondary,
              title: '开源许可',
              subtitle: '查看使用的第三方库及许可',
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppConstants.appName,
                applicationVersion: version,
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: SpacingTokens.xl),

            // 底部版权声明
            Center(
              child: Text(
                '© 2024-2026 韵算 PoeMath\n'
                '数据存储于本地，不收集任何个人信息',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  height: 1.8,
                ),
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (ctx, scrollController) {
            return SafeArea(
              child: Column(
                children: [
                  // 拖拽指示器
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SpacingTokens.sm,
                    ),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.md,
                    ),
                    child: Text(
                      '隐私政策',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      child: Text(
                        _privacyPolicyText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.8,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static const String _privacyPolicyText = '''
韵算 (PoeMath) 隐私政策

最后更新日期：2026年7月

一、信息收集

韵算是一款纯本地应用，我们不会收集、传输或存储您的任何个人信息到远程服务器。

所有学习数据（包括学习进度、成就记录、练习历史等）均存储在您的设备本地。

二、数据存储

• 应用使用 Hive 数据库将所有数据存储在设备本地
• 您可以通过"备份与恢复"功能导出数据到本地文件
• 您可以选择通过 WebDAV 将数据同步到您自己的云端服务器

三、第三方服务

• 应用不集成任何第三方分析、广告或追踪服务
• TTS（文字转语音）功能使用系统内置引擎，不传输数据

四、儿童隐私

本应用面向儿童用户群体。我们严格遵守儿童隐私保护原则：
• 不收集儿童的个人信息
• 不包含任何广告内容
• 不包含应用内购买
• 不包含社交功能

五、数据删除

您可以随时通过以下方式删除所有数据：
• 在应用内切换或删除学习档案
• 卸载应用（将删除所有本地数据）

六、政策更新

我们可能会不时更新本隐私政策。更新后的政策将随应用新版本发布。

七、联系我们

如果您对本隐私政策有任何疑问，请通过应用商店页面联系我们。''';
}
