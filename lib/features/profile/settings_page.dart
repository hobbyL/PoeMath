// lib/features/profile/settings_page.dart
//
// 层级：features/profile
// 职责：应用设置页 — 主题、音频、显示等设置项逐行展示。

import 'package:flutter/material.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/features/profile/parent_protection_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/backup_restore_page.dart';
import 'package:poemath/features/profile/cloud_sync_page.dart';
import 'package:poemath/features/profile/notification_settings_page.dart';
import 'package:poemath/features/profile/practice_settings_page.dart';
import 'package:poemath/features/profile/learning_background_page.dart';
import 'package:poemath/features/profile/speech_recognition_settings_page.dart';
import 'package:poemath/features/profile/tts_settings_page.dart';
import 'package:poemath/features/profile/ai_settings_page.dart';

/// 设置页分区。
///
/// 分组原则是「谁管什么」：同一分区内的项服务同一类决策，不同分区的项
/// 不应有语义重叠。历史上的 `learning` 曾同时装学习背景、练习参数、通知
/// 与 AI 配置四件不相干的事，`appearance` 曾装与外观无关的项，均已按
/// 此原则拆开。
///
/// **本文件内每个分区的 render 代码必须连续排列**（见 `build` 的注释）：
/// 早先按"功能"顺序撰写，导致同一分区的 widget 散落在数百行之间，新增
/// 一项时极易放错分区。
enum _SettingsSection {
  hub,
  learning,
  ai,
  speech,
  appearance,
  data,
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key}) : _section = _SettingsSection.hub;

  const SettingsPage._category(this._section);

  final _SettingsSection _section;

  /// 将原始 voice name 映射为友好名称（用于 subtitle 显示）。
  static String _friendlyVoiceName(String name) {
    final lower = name.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
    const localeMap = {
      'zh': '中文语音',
      'zhcn': '普通话',
      'zhtw': '台湾语音',
      'zhhk': '粤语',
    };
    return localeMap[lower] ?? name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subject = ref.watch(activeSubjectProvider);
    final mode = ref.watch(themeModeProvider);
    final settingsRepo = ref.watch(settingsRepositoryProvider);

    final isDark = switch (mode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };

    final subjectLabel = switch (subject) {
      AppSubject.poem => '国风水墨',
      AppSubject.math => '童趣马卡龙',
    };

    final modeLabel = switch (mode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };

    // 音频设置 subtitle
    final rawVoiceName = settingsRepo.ttsVoice?['name'];
    // 如果 voiceName 是纯 locale code（如 "zh"），映射为友好名称
    final voiceLabel =
        rawVoiceName != null ? _friendlyVoiceName(rawVoiceName) : null;
    final audioSubtitle = voiceLabel != null
        ? '语速 ${settingsRepo.ttsSpeed.toStringAsFixed(1)} · $voiceLabel'
        : '语速 ${settingsRepo.ttsSpeed.toStringAsFixed(1)}';

    final pageTitle = switch (_section) {
      _SettingsSection.hub => '设置',
      _SettingsSection.learning => '学习与内容',
      _SettingsSection.ai => 'AI 设置',
      _SettingsSection.speech => '语音与音频',
      _SettingsSection.appearance => '外观与反馈',
      _SettingsSection.data => '数据与同步',
    };

    return Scaffold(
      appBar: AppBar(title: Text(pageTitle)),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          // 编排约定：**每个分区的 render 代码连续排列**，分区之间用
          // 注释分隔。新增设置项时整块加进对应分区即可，不必在文件里
          // 寻找散落的 `if (_section == ...)`。
          //
          // 分区顺序即 hub 页入口顺序，按「先个人/内容，后设备/系统」：
          // 家长保护 → 学习 → AI → 语音 → 外观 → 提醒 → 数据 → 关于。
          children: <Widget>[
            // ==================== hub：分组入口 ====================
            if (_section == _SettingsSection.hub) ...[
              AppTile(
                icon: Icons.lock_outline,
                iconColor: theme.colorScheme.primary,
                title: '家长保护与云额度',
                subtitle: '可选 PIN、恢复码与每日请求次数',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) => const ParentAccessBoundary(
                      child: ParentProtectionPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.menu_book_outlined,
                iconColor: theme.colorScheme.primary,
                title: '学习与内容',
                subtitle: '学习背景与练习参数',
                onTap: () => _openSection(context, _SettingsSection.learning),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.smart_toy_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: 'AI 设置',
                subtitle: settingsRepo.llmProviders.isEmpty
                    ? '未配置'
                    : '已配置 ${settingsRepo.llmProviders.length} 个服务',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) =>
                        const ParentAccessBoundary(child: AiSettingsPage()),
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.record_voice_over_outlined,
                iconColor: theme.colorScheme.secondary,
                title: '语音与音频',
                subtitle: '朗读音色与语音识别',
                onTap: () => _openSection(context, _SettingsSection.speech),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.palette_outlined,
                iconColor: theme.colorScheme.primary,
                title: '外观与反馈',
                subtitle: '主题、明暗模式、音效与触觉',
                onTap: () => _openSection(context, _SettingsSection.appearance),
              ),
              const SizedBox(height: SpacingTokens.sm),
              // 「通知提醒」直接进通知设置页。原实现先开一个只含一个
              // 入口的「提醒」分组页、再点进去 —— 单入口的中间页纯属
              // 多一次点击。
              AppTile(
                icon: Icons.notifications_outlined,
                iconColor: theme.colorScheme.secondary,
                title: '通知提醒',
                subtitle: '学习提醒与每周报告',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) => const ParentAccessBoundary(
                      child: NotificationSettingsPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.cloud_sync_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: '数据与同步',
                subtitle: '本地备份与 WebDAV 云端同步',
                onTap: () => _openSection(context, _SettingsSection.data),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.info_outline,
                iconColor: theme.colorScheme.onSurfaceVariant,
                title: '关于韵算',
                subtitle: '版本信息、更新与隐私政策',
                onTap: () => context.push(AppRoutes.about),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],

            // ==================== 学习与内容 ====================
            // 学习者档案 + 练习参数 + 内容展示偏好（拼音）。这三者共同
            // 决定"练什么、怎么练、看到什么"，故归一组。
            if (_section == _SettingsSection.learning) ...[
              AppTile(
                icon: Icons.school_outlined,
                iconColor: theme.colorScheme.primary,
                title: '学习背景',
                subtitle:
                    '${settingsRepo.selectedGrade} 年级${settingsRepo.selectedSemester}学期',
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    fadeSlideRoute(
                      builder: (_) => const ParentAccessBoundary(
                        child: LearningBackgroundPage(),
                      ),
                    ),
                  );
                  if (context.mounted) {
                    ref.invalidate(settingsRepositoryProvider);
                  }
                },
              ),
              const SizedBox(height: SpacingTokens.sm),
              _buildPracticeSettings(context, ref),
              const SizedBox(height: SpacingTokens.md),
            ],

            // ==================== AI 设置 ====================
            // AI 有独立的页面群（厂商 / 模型 / 提示词 / 助手），从 hub
            // 直接进入其枢纽页，不再作为某个分区的二级项。
            if (_section == _SettingsSection.ai)
              AppTile(
                icon: Icons.smart_toy_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: 'AI 设置',
                subtitle: settingsRepo.llmProviders.isEmpty
                    ? '未配置'
                    : '已配置 ${settingsRepo.llmProviders.length} 个服务',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) =>
                        const ParentAccessBoundary(child: AiSettingsPage()),
                  ),
                ),
              ),
            if (_section == _SettingsSection.ai)
              const SizedBox(height: SpacingTokens.md),

            // ==================== 语音与音频 ====================
            // 两项都是带子页的重配置（音色/密钥），与「外观与反馈」里的
            // 即时开关（音效/触觉）性质不同，故分开。
            if (_section == _SettingsSection.speech) ...[
              AppTile(
                icon: Icons.volume_up_outlined,
                iconColor: theme.semantic.caution,
                title: '音频设置',
                subtitle: audioSubtitle,
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) =>
                        const ParentAccessBoundary(child: TtsSettingsPage()),
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.record_voice_over_outlined,
                iconColor: theme.colorScheme.primary,
                title: '语音识别设置',
                subtitle: '腾讯云识别密钥与真实录音测试',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) => const ParentAccessBoundary(
                      child: SpeechRecognitionSettingsPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],

            // ==================== 外观与反馈 ====================
            // 主题/明暗 + 操作反馈（音效、触觉）。共同点是"即时生效的观感
            // 与反馈开关"，无子页。
            if (_section == _SettingsSection.appearance) ...[
              AppTile(
                icon: Icons.palette_outlined,
                iconColor: theme.colorScheme.primary,
                title: '主题设置',
                subtitle: subjectLabel,
                onTap: () => _showSubjectPicker(context, ref, subject),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: isDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                iconColor: theme.colorScheme.secondary,
                title: '外观模式',
                subtitle: modeLabel,
                onTap: () => _showThemeModePicker(context, ref, mode),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.music_note_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: '音效',
                subtitle: settingsRepo.soundEnabled ? '已开启' : '已关闭',
                trailing: Switch(
                  value: settingsRepo.soundEnabled,
                  onChanged: (v) => _writeSetting(context, ref, '音效', () async {
                    await settingsRepo.setSoundEnabled(v);
                  }),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.vibration_outlined,
                iconColor: theme.colorScheme.error,
                title: '触觉反馈',
                subtitle: settingsRepo.hapticEnabled ? '已开启（需真机体验）' : '已关闭',
                trailing: Switch(
                  value: settingsRepo.hapticEnabled,
                  onChanged: (v) =>
                      _writeSetting(context, ref, '触觉反馈', () async {
                    await settingsRepo.setHapticEnabled(v);
                    // 开启时触发一次测试震动
                    if (v) {
                      await HapticFeedback.mediumImpact();
                    }
                  }),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],

            // ==================== 数据与同步 ====================
            if (_section == _SettingsSection.data) ...[
              AppTile(
                icon: Icons.folder_outlined,
                iconColor: theme.colorScheme.primary,
                title: '备份与恢复',
                subtitle: '导出或恢复学习数据',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) =>
                        const ParentAccessBoundary(child: BackupRestorePage()),
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.cloud_sync_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: '云端同步',
                subtitle: '通过 WebDAV 同步数据',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) =>
                        const ParentAccessBoundary(child: CloudSyncPage()),
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],
          ],
        ),
      ),
    );
  }

  /// 执行一次设置写入，并在成功后刷新 provider 让开关文案同步。
  ///
  /// 收拢原先散落在三个 Switch 的 `onChanged` 里的同一段逻辑，补上两处原实现
  /// 的缺口：
  ///
  /// 1. **写入失败不再静默**：`setPinyinVisible` 等直接 `Hive.put`，磁盘满或
  ///    Box 损坏会抛。原先异常从 `onChanged` 冒泡到框架，用户只看到开关弹回、
  ///    无任何解释。这里捕获后提示，且**不** invalidate —— 失败时 provider 里
  ///    仍是旧值，开关自动回弹，界面与真实状态一致。
  /// 2. **无谓的 invalidate 不再执行**：原实现在 await 之后无条件 invalidate，
  ///    而它紧跟着失败也会执行，把新值推给 provider 造成「界面已开、落盘失败」
  ///    的假象。
  ///
  /// [label] 仅用于日志与提示文案；[write] 是真正的写入动作（可含附带效果，
  /// 如触觉反馈的测试震动）。
  ///
  /// 本类是 `ConsumerWidget`（无 State），故 `context`/`ref` 由调用处显式传入
  /// —— 不能用成员访问，也不应把 `BuildContext` 存进字段。
  Future<void> _writeSetting(
    BuildContext context,
    WidgetRef ref,
    String label,
    Future<void> Function() write,
  ) async {
    try {
      await write();
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '$label 设置保存失败',
        tag: 'SettingsPage',
        error: error,
        stackTrace: stackTrace,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$label设置保存失败，请重试')));
      return;
    }
    if (!context.mounted) return;
    ref.invalidate(settingsRepositoryProvider);
  }

  void _openSection(BuildContext context, _SettingsSection section) {
    Navigator.push<void>(
      context,
      fadeSlideRoute(
          builder: (_) =>
              ParentAccessBoundary(child: SettingsPage._category(section)),),
    );
  }

  void _showSubjectPicker(
    BuildContext context,
    WidgetRef ref,
    AppSubject current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '主题风格',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<AppSubject>(
                      groupValue: current,
                      onChanged: (v) {
                        if (v == null) return;
                        ref.read(activeSubjectProvider.notifier).setSubject(v);
                        Navigator.pop(ctx);
                      },
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          RadioListTile<AppSubject>(
                            title: Text('国风水墨主题'),
                            value: AppSubject.poem,
                          ),
                          RadioListTile<AppSubject>(
                            title: Text('童趣马卡龙主题'),
                            value: AppSubject.math,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showThemeModePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '外观模式',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<ThemeMode>(
                      groupValue: current,
                      onChanged: (v) {
                        if (v == null) return;
                        ref.read(themeModeProvider.notifier).setMode(v);
                        Navigator.pop(ctx);
                      },
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          RadioListTile<ThemeMode>(
                            title: Text('跟随系统'),
                            secondary: Icon(Icons.settings_suggest_outlined),
                            value: ThemeMode.system,
                          ),
                          RadioListTile<ThemeMode>(
                            title: Text('浅色'),
                            secondary: Icon(Icons.light_mode_outlined),
                            value: ThemeMode.light,
                          ),
                          RadioListTile<ThemeMode>(
                            title: Text('深色'),
                            secondary: Icon(Icons.dark_mode_outlined),
                            value: ThemeMode.dark,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPracticeSettings(
    BuildContext context,
    WidgetRef ref,
  ) {
    final settingsRepo = ref.watch(settingsRepositoryProvider);
    final poemGoal = ref.watch(dailyPoemGoalProvider);
    final mathGoal = ref.watch(dailyMathGoalProvider);
    final batchSize = settingsRepo.mathBatchSize;
    final theme = Theme.of(context);

    return AppTile(
      icon: Icons.tune_outlined,
      iconColor: theme.semantic.caution,
      title: '练习设置',
      subtitle: '每组 $batchSize 题 · 诗词 $poemGoal 首 · 口算 $mathGoal 题',
      onTap: () => Navigator.push<void>(
        context,
        fadeSlideRoute(
            builder: (_) =>
                const ParentAccessBoundary(child: PracticeSettingsPage()),),
      ),
    );
  }
}
