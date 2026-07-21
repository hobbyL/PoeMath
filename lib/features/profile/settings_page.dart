// lib/features/profile/settings_page.dart
//
// 层级：features/profile
// 职责：应用设置页 — 主题、音频、显示等设置项逐行展示。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/backup_restore_page.dart';
import 'package:poemath/features/profile/cloud_sync_page.dart';
import 'package:poemath/features/profile/notification_settings_page.dart';
import 'package:poemath/features/profile/practice_settings_page.dart';
import 'package:poemath/features/profile/speech_recognition_settings_page.dart';
import 'package:poemath/features/profile/tts_settings_page.dart';

enum _SettingsSection { hub, appearance, sound, learning, data }

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
      _SettingsSection.appearance => '外观与显示',
      _SettingsSection.sound => '声音与交互',
      _SettingsSection.learning => '学习与提醒',
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
          children: <Widget>[
            if (_section == _SettingsSection.hub)
              AppTile(
                icon: Icons.palette_outlined,
                iconColor: theme.colorScheme.primary,
                title: '外观与显示',
                subtitle: '主题、明暗模式与拼音显示',
                onTap: () => _openSection(
                  context,
                  _SettingsSection.appearance,
                ),
              ),
            if (_section == _SettingsSection.hub)
              const SizedBox(height: SpacingTokens.sm),
            if (_section == _SettingsSection.hub)
              AppTile(
                icon: Icons.volume_up_outlined,
                iconColor: theme.semantic.caution,
                title: '声音与交互',
                subtitle: '朗读、语音识别、音效与触觉反馈',
                onTap: () => _openSection(context, _SettingsSection.sound),
              ),
            if (_section == _SettingsSection.hub)
              const SizedBox(height: SpacingTokens.sm),
            if (_section == _SettingsSection.hub)
              AppTile(
                icon: Icons.tune_outlined,
                iconColor: theme.colorScheme.secondary,
                title: '学习与提醒',
                subtitle: '练习设置、每日目标与学习提醒',
                onTap: () => _openSection(context, _SettingsSection.learning),
              ),
            if (_section == _SettingsSection.hub)
              const SizedBox(height: SpacingTokens.sm),
            if (_section == _SettingsSection.hub)
              AppTile(
                icon: Icons.cloud_sync_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: '数据与同步',
                subtitle: '本地备份与 WebDAV 云端同步',
                onTap: () => _openSection(context, _SettingsSection.data),
              ),
            if (_section == _SettingsSection.hub)
              const SizedBox(height: SpacingTokens.sm),

            // 主题设置
            if (_section == _SettingsSection.appearance)
              AppTile(
                icon: Icons.palette_outlined,
                iconColor: theme.colorScheme.primary,
                title: '主题设置',
                subtitle: subjectLabel,
                onTap: () => _showSubjectPicker(context, ref, subject),
              ),
            if (_section == _SettingsSection.appearance)
              const SizedBox(height: SpacingTokens.sm),

            // 外观模式
            if (_section == _SettingsSection.appearance)
              AppTile(
                icon: isDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                iconColor: theme.colorScheme.secondary,
                title: '外观模式',
                subtitle: modeLabel,
                onTap: () => _showThemeModePicker(context, ref, mode),
              ),
            if (_section == _SettingsSection.appearance)
              const SizedBox(height: SpacingTokens.sm),

            // 音频设置（语速 + 音色 → 子页面）
            if (_section == _SettingsSection.sound)
              AppTile(
                icon: Icons.volume_up_outlined,
                iconColor: theme.semantic.caution,
                title: '音频设置',
                subtitle: audioSubtitle,
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) => const TtsSettingsPage(),
                  ),
                ),
              ),
            if (_section == _SettingsSection.sound)
              const SizedBox(height: SpacingTokens.sm),

            // 拼音显示
            if (_section == _SettingsSection.appearance)
              AppTile(
                icon: Icons.text_fields_outlined,
                iconColor: theme.semantic.success,
                title: '拼音显示',
                subtitle: settingsRepo.pinyinVisible ? '已开启' : '已关闭',
                trailing: Switch(
                  value: settingsRepo.pinyinVisible,
                  onChanged: (v) async {
                    await settingsRepo.setPinyinVisible(v);
                    if (context.mounted) {
                      ref.invalidate(settingsRepositoryProvider);
                    }
                  },
                ),
              ),
            if (_section == _SettingsSection.appearance)
              const SizedBox(height: SpacingTokens.md),

            // 语音识别设置
            if (_section == _SettingsSection.sound)
              AppTile(
                icon: Icons.record_voice_over_outlined,
                iconColor: theme.colorScheme.primary,
                title: '语音识别设置',
                subtitle: settingsRepo.tencentAsrHighAccuracyEnabled
                    ? '高精度云端识别已开启'
                    : '默认使用离线识别',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) => const SpeechRecognitionSettingsPage(),
                  ),
                ),
              ),
            if (_section == _SettingsSection.sound)
              const SizedBox(height: SpacingTokens.sm),

            // 音效
            if (_section == _SettingsSection.sound)
              AppTile(
                icon: Icons.music_note_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: '音效',
                subtitle: settingsRepo.soundEnabled ? '已开启' : '已关闭',
                trailing: Switch(
                  value: settingsRepo.soundEnabled,
                  onChanged: (v) async {
                    await settingsRepo.setSoundEnabled(v);
                    if (context.mounted) {
                      ref.invalidate(settingsRepositoryProvider);
                    }
                  },
                ),
              ),
            if (_section == _SettingsSection.sound)
              const SizedBox(height: SpacingTokens.sm),

            // 触觉反馈
            if (_section == _SettingsSection.sound)
              AppTile(
                icon: Icons.vibration_outlined,
                iconColor: theme.colorScheme.error,
                title: '触觉反馈',
                subtitle: settingsRepo.hapticEnabled ? '已开启（需真机体验）' : '已关闭',
                trailing: Switch(
                  value: settingsRepo.hapticEnabled,
                  onChanged: (v) async {
                    await settingsRepo.setHapticEnabled(v);
                    if (context.mounted) {
                      ref.invalidate(settingsRepositoryProvider);
                    }
                    // 开启时触发一次测试震动
                    if (v) {
                      await HapticFeedback.mediumImpact();
                    }
                  },
                ),
              ),
            if (_section == _SettingsSection.sound)
              const SizedBox(height: SpacingTokens.md),

            // 练习设置（每组题数 + 难度 + 每日目标）
            if (_section == _SettingsSection.learning)
              _buildPracticeSettings(context, ref),
            if (_section == _SettingsSection.learning)
              const SizedBox(height: SpacingTokens.sm),

            // 通知设置（学习提醒 + 周报推送 → 子页面）
            if (_section == _SettingsSection.learning)
              _buildNotificationSettings(context),
            if (_section == _SettingsSection.learning)
              const SizedBox(height: SpacingTokens.md),

            // 备份与恢复
            if (_section == _SettingsSection.data)
              AppTile(
                icon: Icons.folder_outlined,
                iconColor: theme.colorScheme.primary,
                title: '备份与恢复',
                subtitle: '导出或恢复学习数据',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) => const BackupRestorePage(),
                  ),
                ),
              ),
            if (_section == _SettingsSection.data)
              const SizedBox(height: SpacingTokens.sm),

            // 云端同步
            if (_section == _SettingsSection.data)
              AppTile(
                icon: Icons.cloud_sync_outlined,
                iconColor: theme.colorScheme.tertiary,
                title: '云端同步',
                subtitle: '通过 WebDAV 同步数据',
                onTap: () => Navigator.push<void>(
                  context,
                  fadeSlideRoute(
                    builder: (_) => const CloudSyncPage(),
                  ),
                ),
              ),
            if (_section == _SettingsSection.data)
              const SizedBox(height: SpacingTokens.md),

            // 关于
            if (_section == _SettingsSection.hub)
              AppTile(
                icon: Icons.info_outline,
                iconColor: theme.colorScheme.onSurfaceVariant,
                title: '关于韵算',
                subtitle: '版本信息、更新与隐私政策',
                onTap: () => context.push(AppRoutes.about),
              ),
            if (_section == _SettingsSection.hub)
              const SizedBox(height: SpacingTokens.md),
          ],
        ),
      ),
    );
  }

  void _openSection(BuildContext context, _SettingsSection section) {
    Navigator.push<void>(
      context,
      fadeSlideRoute(builder: (_) => SettingsPage._category(section)),
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
        fadeSlideRoute(builder: (_) => const PracticeSettingsPage()),
      ),
    );
  }

  Widget _buildNotificationSettings(BuildContext context) {
    final theme = Theme.of(context);
    final svc = NotificationService.instance;
    final reminderOn = svc.isReminderEnabled;
    final weeklyOn = svc.isWeeklyReportEnabled;

    String subtitle;
    if (reminderOn && weeklyOn) {
      final h = svc.reminderHour.toString().padLeft(2, '0');
      final m = svc.reminderMinute.toString().padLeft(2, '0');
      subtitle = '提醒 $h:$m · 周报已开启';
    } else if (reminderOn) {
      final h = svc.reminderHour.toString().padLeft(2, '0');
      final m = svc.reminderMinute.toString().padLeft(2, '0');
      subtitle = '提醒 $h:$m · 周报已关闭';
    } else if (weeklyOn) {
      subtitle = '提醒已关闭 · 周报已开启';
    } else {
      subtitle = '提醒已关闭 · 周报已关闭';
    }

    return AppTile(
      icon: Icons.notifications_outlined,
      iconColor: theme.colorScheme.secondary,
      title: '通知设置',
      subtitle: subtitle,
      onTap: () => Navigator.push<void>(
        context,
        fadeSlideRoute(builder: (_) => const NotificationSettingsPage()),
      ),
    );
  }
}
