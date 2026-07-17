// lib/features/profile/about_page.dart
//
// 层级：features/profile
// 职责：关于页面 — 展示应用版本、开发者信息、隐私政策和开源许可。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:poemath/core/config/app_config.dart';
import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _packageInfo;

  /// 缓存隐私政策加载，避免 BottomSheet 重建时重复读 asset。
  Future<String>? _privacyPolicyFuture;

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
              onTap: () => context.go(AppRoutes.poemTab),
            ),
            const SizedBox(height: SpacingTokens.sm),
            AppTile(
              icon: Icons.calculate_outlined,
              iconColor: theme.colorScheme.secondary,
              title: '口算练习',
              subtitle: '多难度分级，错题本自动归纳',
              onTap: () => context.go(AppRoutes.mathTab),
            ),
            const SizedBox(height: SpacingTokens.sm),
            AppTile(
              icon: Icons.emoji_events_outlined,
              iconColor: theme.colorScheme.tertiary,
              title: '成就体系',
              subtitle: '44枚成就勋章，记录成长足迹',
              onTap: () => context.push(AppRoutes.achievements),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 检查更新
            AppTile(
              icon: Icons.system_update_outlined,
              iconColor: theme.colorScheme.onSurfaceVariant,
              title: '检查更新',
              subtitle: AppConfig.hasUpdateCheckUrl
                  ? '查看新版本并下载安装'
                  : '更新检查未配置',
              onTap: AppConfig.hasUpdateCheckUrl
                  ? () => context.push(AppRoutes.update)
                  : null,
            ),
            const SizedBox(height: SpacingTokens.sm),

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
    _privacyPolicyFuture ??= _loadPrivacyPolicyText();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (ctx, scrollController) {
            return SafeArea(
              child: Column(
                children: [
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
                    child: FutureBuilder<String>(
                      future: _privacyPolicyFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState !=
                            ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final text = snapshot.hasError
                            ? _privacyPolicyFallback
                            : (snapshot.data ?? _privacyPolicyFallback);
                        return SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(SpacingTokens.md),
                          child: Text(
                            text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.7,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                        );
                      },
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

  /// 与 `docs/PRIVACY.md` 同源：打包资源 `assets/legal/privacy_policy.md`。
  static Future<String> _loadPrivacyPolicyText() async {
    final raw = await rootBundle.loadString(_privacyPolicyAsset);
    return _markdownToPlainText(raw);
  }

  /// 轻量去掉 Markdown 标记，便于 BottomSheet 纯文本阅读。
  static String _markdownToPlainText(String markdown) {
    final lines = markdown.split('\n');
    final out = <String>[];
    for (final line in lines) {
      var s = line;
      // 跳过仅含引用提示的仓库维护说明行（应用内无需展示）
      if (s.startsWith('> 本文档与应用内') ||
          s.startsWith('> 修改隐私说明时')) {
        continue;
      }
      s = s.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
      s = s.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'),
        (m) => m.group(1) ?? '',
      );
      s = s.replaceAllMapped(
        RegExp(r'`([^`]+)`'),
        (m) => m.group(1) ?? '',
      );
      s = s.replaceFirst(RegExp(r'^>\s?'), '');
      // 表格分隔线省略
      if (RegExp(r'^\|[\s:-]+\|$').hasMatch(s.replaceAll(' ', ''))) {
        continue;
      }
      out.add(s);
    }
    return out.join('\n').trim();
  }

  static const String _privacyPolicyAsset =
      'assets/legal/privacy_policy.md';

  /// Asset 加载失败时的精简兜底（与正式政策原则一致，避免空白）。
  static const String _privacyPolicyFallback = '''
韵算 (PoeMath) 隐私政策

最后更新：2026 年 7 月 17 日

一、产品原则
韵算为离线优先儿童学习应用。诗词、口算、公式、打卡等核心功能不依赖网络。不向开发者服务器收集个人信息；无广告、无内购、无分析追踪 SDK。

二、本地数据
学习进度、错题、成就等默认仅存本机。卸载将删除本地数据；请先使用「备份与恢复」导出。

三、可选能力（需主动使用）
• 本地备份/恢复：导出 JSON 或系统分享，不经开发者服务器
• WebDAV：仅连接您配置的服务器；凭据加密存本机
• 检查更新：仅在已配置更新地址且您点击后下载/校验/安装 APK
• 诗词跟读：需麦克风，使用系统语音识别
• 学习提醒：需通知权限，本机定时通知

四、权限
可能涉及：网络、安装应用包、麦克风、通知、振动、开机完成（恢复提醒）。不申请通讯录、定位、短信等无关权限。

五、儿童隐私
面向 6–12 岁；建议家长管理 WebDAV、更新与敏感权限。

六、联系
我的 → 关于 → 隐私政策；或通过开源仓库 Issue。

完整条款见应用资源 assets/legal/privacy_policy.md 与仓库 docs/PRIVACY.md。
''';
}
