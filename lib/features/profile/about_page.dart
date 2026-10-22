// lib/features/profile/about_page.dart
//
// 层级：features/profile
// 职责：关于页面 — 展示应用版本、开发者信息、诊断日志导出、隐私政策和开源许可。

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/diagnostics/diagnostic_buffer.dart';
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

  /// 诊断缓冲当前条数（`initState` / 导出后刷新，供 AppTile 副标题显示）。
  int _diagnosticCount = 0;
  bool _exportingDiagnostics = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _diagnosticCount = DiagnosticBuffer.instance.length;
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
      // 本页不用 AppBar：顶部只放一个「关于」标题，占掉整条高度却不承载
      // 交互。改为内容顶格 + 返回按钮浮动左上角（见下方 Positioned）。
      //
      // `SafeArea` 必须有：本页是顶级全屏路由，没有它内容会顶到状态栏下。
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedPageBody(
              // 顶部留出浮动返回按钮那一行的高度。
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.lg,
                SpacingTokens.sm,
                SpacingTokens.lg,
                SpacingTokens.lg,
              ),
              children: <Widget>[
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
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Text(
                        version,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),

                // 应用介绍
                ColoredCard(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      // 不再单设「应用介绍」标题行：这张卡里只有一段文案，
                      // 标题只是把同一件事说两遍（卡片位置已表明它是什么）。
                      children: [
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
                // 与其他 AppTile 之间保持一致（sm）；这里原为 md，导致
                // 「成就体系 → 导出诊断日志」明显比别处疏。
                const SizedBox(height: SpacingTokens.sm),

                // 导出诊断日志（生产环境崩溃/异常排查入口）。
                //
                // 刻意**不加家长门禁**：诊断文本已在写入时 scrub，且不含学习数据，
                // 不构成儿童隐私面；而加门禁恰恰会在用户最需要导出的时刻（应用
                // 刚崩溃/家长不在场）把他卡住。这与 backup_restore_page.dart 的
                // 处理有意不同。
                AppTile(
                  icon: Icons.bug_report_outlined,
                  iconColor: theme.colorScheme.onSurfaceVariant,
                  title: '导出诊断日志',
                  subtitle: _diagnosticCount == 0
                      ? '暂无可导出的日志'
                      : '最近 $_diagnosticCount 条记录',
                  onTap: (_diagnosticCount == 0 || _exportingDiagnostics)
                      ? null
                      : () => _exportDiagnostics(context),
                ),
                const SizedBox(height: SpacingTokens.sm),

                // 检查更新
                //
                // 入口**始终可点**：是否配置更新地址由更新页自己告知
                //（`UpdateClient.fetchLatest` 未配置时抛
                // `UpdateConfigurationException`，页面经 `friendlyUpdateError`
                // 显示「当前安装包未配置更新检查地址。」）。
                //
                // 早先此处按 `hasUpdateCheckUrl` 把 `onTap` 设为 null，未配置的
                // 构建（如本地 debug，`UPDATE_CHECK_URL` 未经 --dart-define 注入）
                // 点上去毫无反应，用户无法区分「坏了」与「没配」。
                AppTile(
                  icon: Icons.system_update_outlined,
                  iconColor: theme.colorScheme.onSurfaceVariant,
                  title: '检查更新',
                  subtitle: '查看新版本并下载安装',
                  onTap: () => context.push(AppRoutes.update),
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
                  subtitle: '查看第三方库、音效及许可',
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      height: 1.8,
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.lg),
              ],
            ),

            // 返回按钮浮动固定在左上角（原 AppBar 的自动返回）。
            Positioned(
              top: SpacingTokens.xs,
              left: SpacingTokens.xs,
              child: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 导出诊断缓冲为纯文本文件（保存到设备 / 分享）。
  ///
  /// 复用 `backup_restore_page.dart` 的 bottom sheet + 双 `AppTile` 模式。
  /// 文本已由 `DiagnosticBuffer` 在写入时 scrub；此处不再过滤，因为
  /// 过滤口径只应有一处（`logging-guidelines.md` 的 Never Log 清单照旧）。
  Future<void> _exportDiagnostics(BuildContext context) async {
    if (_exportingDiagnostics) return;
    setState(() => _exportingDiagnostics = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '导出诊断日志',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheet).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.md),
                AppTile(
                  icon: Icons.save_alt_rounded,
                  iconColor: Theme.of(sheet).colorScheme.primary,
                  title: '保存到设备',
                  subtitle: '选择本地目录保存诊断文本',
                  onTap: () => Navigator.pop(sheet, 'save'),
                ),
                const SizedBox(height: SpacingTokens.sm),
                AppTile(
                  icon: Icons.share_rounded,
                  iconColor: Theme.of(sheet).colorScheme.primary,
                  title: '分享',
                  subtitle: '通过其他应用发送诊断文本',
                  onTap: () => Navigator.pop(sheet, 'share'),
                ),
              ],
            ),
          ),
        ),
      );
      if (action == null || !mounted) return;

      final text = await _buildDiagnosticsText();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'poemath_diagnostics_$timestamp.txt';

      if (action == 'save') {
        await FilePicker.saveFile(
          dialogTitle: '保存诊断日志',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['txt'],
          bytes: Uint8List.fromList(utf8.encode(text)),
        );
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        try {
          await file.writeAsString(text);
          if (!mounted) return;
          await SharePlus.instance
              .share(ShareParams(files: [XFile(file.path)]));
        } finally {
          if (await file.exists()) await file.delete();
        }
      }
      if (!mounted) return;
      scaffold.showSnackBar(const SnackBar(content: Text('诊断日志导出完成')));
    } on Object catch (error) {
      if (mounted) {
        scaffold.showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _exportingDiagnostics = false;
          _diagnosticCount = DiagnosticBuffer.instance.length;
        });
      }
    }
  }

  /// 诊断导出文本：头部元信息 + 缓冲正文。
  ///
  /// 头部带上 `versionName + versionCode + tagName` —— release 包经
  /// `--obfuscate` 后堆栈不可读，必须靠版本信息在 CI 产物里找到对应的
  /// `symbols-<tag>` 归档才能还原（design.md §4.3）。
  Future<String> _buildDiagnosticsText() async {
    final info = _packageInfo ?? await PackageInfo.fromPlatform();
    final buffer = StringBuffer()
      ..writeln('${AppConstants.appName} (${AppConstants.appNameEn}) 诊断日志')
      ..writeln('版本：v${info.version} (${info.buildNumber})')
      ..writeln('数据版本：${AppConstants.dataVersion}')
      ..writeln('导出时间：${DateTime.now().toIso8601String()}')
      ..writeln('记录条数：${DiagnosticBuffer.instance.length}')
      ..writeln('搭建于内存缓冲，应用重启即清空')
      ..writeln('─' * 32)
      ..writeln();
    buffer.write(DiagnosticBuffer.instance.exportAsText());
    return buffer.toString();
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
                  const SizedBox(height: SpacingTokens.md),
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
                        if (snapshot.connectionState != ConnectionState.done) {
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

  /// 隐私政策正文：`assets/legal/privacy_policy.md`（单一来源）。
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
      if (s.startsWith('> 本文档与应用内') || s.startsWith('> 修改隐私说明时')) {
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

  static const String _privacyPolicyAsset = 'assets/legal/privacy_policy.md';

  /// Asset 加载失败时的精简兜底（与正式政策原则一致，避免空白）。
  static const String _privacyPolicyFallback = '''
韵算 (PoeMath) 隐私政策摘要
最后更新：2026 年 10 月 22 日

核心诗词与数学学习离线运行，不向开发者收集个人信息，无广告和追踪 SDK。
学习记录主要保存本机，Hive 内容加密；本地历史快照以独立设备密钥整体加密。
外部备份：设置口令后整体加密；未设口令为明文 JSON，不含安全凭据。WebDAV 仅连接您配置的服务器。
配置更新源的版本在启动及恢复前台自动检查版本信息，至少间隔一小时；下载与安装需您主动确认。
可选语音识别、云朗读、AI 讲解/助手发送所需文本或音频到家长配置的第三方服务；助手可能携带您允许的学习背景。应用题出题只发送年级学期、知识点、数量关系类型及情境/句式候选，题面和讲解在本地生成。服务凭据存于设备安全存储，设口令时可加密备份。
AI 调用失败时可尝试同一服务商内已选的其他模型，有效成功后自动保存默认模型及当前显式场景选择；每次发送计入云额度，重试可能增加等待与服务用量。流式正文输出后中断会保留已有内容和错误提示。
麦克风与通知需授权；Android 系统备份取决于您的系统设置。建议家长管理外部服务、备份与权限。
完整政策资源暂时无法加载，请稍后重试。联系渠道：开源仓库 Issue。
''';
}
