// lib/features/profile/settings_page.dart
//
// 层级：features/profile
// 职责：应用设置页 — 主题、音频、显示等设置项逐行展示。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/config/app_config.dart';
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
import 'package:poemath/features/profile/practice_settings_page.dart';
import 'package:poemath/features/profile/tts_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

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
      AppSubject.poem => '诗词',
      AppSubject.math => '口算',
    };

    final modeLabel = switch (mode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };

    // 音频设置 subtitle
    final rawVoiceName = settingsRepo.ttsVoice?['name'];
    // 如果 voiceName 是纯 locale code（如 "zh"），映射为友好名称
    final voiceLabel = rawVoiceName != null
        ? _friendlyVoiceName(rawVoiceName)
        : null;
    final audioSubtitle = voiceLabel != null
        ? '语速 ${settingsRepo.ttsSpeed.toStringAsFixed(1)} · $voiceLabel'
        : '语速 ${settingsRepo.ttsSpeed.toStringAsFixed(1)}';

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          children: <Widget>[
            // 主题设置
            AppTile(
              icon: Icons.palette_outlined,
              iconColor: theme.colorScheme.primary,
              title: '主题设置',
              subtitle: subjectLabel,
              onTap: () => _showSubjectPicker(context, ref, subject),
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 外观模式
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

            // 音频设置（语速 + 音色 → 子页面）
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
            const SizedBox(height: SpacingTokens.sm),

            // 拼音显示
            AppTile(
              icon: Icons.text_fields_outlined,
              iconColor: theme.semantic.success,
              title: '拼音显示',
              subtitle: settingsRepo.pinyinVisible ? '已开启' : '已关闭',
              trailing: Switch(
                value: settingsRepo.pinyinVisible,
                onChanged: (v) async {
                  await settingsRepo.setPinyinVisible(v);
                  ref.invalidate(settingsRepositoryProvider);
                },
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 音效
            AppTile(
              icon: Icons.music_note_outlined,
              iconColor: theme.colorScheme.tertiary,
              title: '音效',
              subtitle: settingsRepo.soundEnabled ? '已开启' : '已关闭',
              trailing: Switch(
                value: settingsRepo.soundEnabled,
                onChanged: (v) async {
                  await settingsRepo.setSoundEnabled(v);
                  ref.invalidate(settingsRepositoryProvider);
                },
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 触觉反馈
            AppTile(
              icon: Icons.vibration_outlined,
              iconColor: theme.colorScheme.error,
              title: '触觉反馈',
              subtitle: settingsRepo.hapticEnabled
                  ? '已开启（需真机体验）'
                  : '已关闭',
              trailing: Switch(
                value: settingsRepo.hapticEnabled,
                onChanged: (v) async {
                  await settingsRepo.setHapticEnabled(v);
                  ref.invalidate(settingsRepositoryProvider);
                  // 开启时触发一次测试震动
                  if (v) {
                    await HapticFeedback.mediumImpact();
                  }
                },
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 练习设置（每组题数 + 难度 + 每日目标）
            _buildPracticeSettings(context, ref),
            const SizedBox(height: SpacingTokens.md),

            // 学习提醒
            const _ReminderTile(),
            // 周报推送
            const _WeeklyReportTile(),
            const SizedBox(height: SpacingTokens.md),

            // 备份与恢复
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
            const SizedBox(height: SpacingTokens.sm),

            // 云端同步
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

            // 关于
            AppTile(
              icon: Icons.info_outline,
              iconColor: theme.colorScheme.onSurfaceVariant,
              title: '关于韵算',
              subtitle: '版本信息、隐私政策',
              onTap: () => context.push(AppRoutes.about),
            ),
            const SizedBox(height: SpacingTokens.md),
          ],
        ),
      ),
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
                            title: Text('诗词'),
                            subtitle: Text('国风水墨主题'),
                            secondary: Icon(Icons.brush_rounded),
                            value: AppSubject.poem,
                          ),
                          RadioListTile<AppSubject>(
                            title: Text('口算'),
                            subtitle: Text('童趣马卡龙主题'),
                            secondary: Icon(Icons.calculate_rounded),
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
                        ref.read(themeModeProvider.notifier).state = v;
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
}

/// 学习提醒设置行 — 开关 + 时间选择。
///
/// 独立 StatefulWidget 以管理通知服务的本地状态。
class _ReminderTile extends StatefulWidget {
  const _ReminderTile();

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile> {
  late bool _enabled;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    final svc = NotificationService.instance;
    _enabled = svc.isReminderEnabled;
    _hour = svc.reminderHour;
    _minute = svc.reminderMinute;
  }

  String get _timeLabel =>
      '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  Future<void> _toggle(bool value) async {
    final svc = NotificationService.instance;
    if (value) {
      final granted = await svc.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要通知权限才能设置提醒')),
          );
        }
        return;
      }
      await svc.scheduleDailyReminder(_hour, _minute);
    } else {
      await svc.cancelDailyReminder();
    }
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      helpText: '选择提醒时间',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });

    if (_enabled) {
      await NotificationService.instance
          .scheduleDailyReminder(_hour, _minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTile(
          icon: Icons.notifications_outlined,
          iconColor: theme.colorScheme.secondary,
          title: '学习提醒',
          subtitle: _enabled ? '每天 $_timeLabel 提醒' : '已关闭',
          trailing: Switch(
            value: _enabled,
            onChanged: _toggle,
          ),
        ),
        if (_enabled) ...[
          const SizedBox(height: SpacingTokens.xs),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: InkWell(
              borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
              onTap: _pickTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md,
                  vertical: SpacingTokens.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    Text(
                      '提醒时间：$_timeLabel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 周报推送开关。
class _WeeklyReportTile extends StatefulWidget {
  const _WeeklyReportTile();

  @override
  State<_WeeklyReportTile> createState() => _WeeklyReportTileState();
}

class _WeeklyReportTileState extends State<_WeeklyReportTile> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = NotificationService.instance.isWeeklyReportEnabled;
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) return;
      await NotificationService.instance.scheduleWeeklyReport();
    } else {
      await NotificationService.instance.cancelWeeklyReport();
    }
    setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppTile(
      icon: Icons.insert_chart_outlined,
      iconColor: theme.colorScheme.tertiary,
      title: '学习周报',
      subtitle: _enabled ? '每周日 18:00 推送' : '已关闭',
      trailing: Switch(
        value: _enabled,
        onChanged: _toggle,
      ),
    );
  }
}