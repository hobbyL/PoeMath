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
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/backup_restore_page.dart';
import 'package:poemath/features/profile/cloud_sync_page.dart';
import 'package:poemath/features/profile/daily_goal_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

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

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
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

            // 音频设置
            AppTile(
              icon: Icons.volume_up_outlined,
              iconColor: ColorTokens.poemGold,
              title: '音频设置',
              subtitle: '语速 ${settingsRepo.ttsSpeed.toStringAsFixed(1)}',
              onTap: () => _showTtsSpeedPicker(context, ref, settingsRepo),
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 拼音显示
            AppTile(
              icon: Icons.text_fields_outlined,
              iconColor: ColorTokens.success,
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

            // 每日目标设置
            _buildDailyGoalSettings(context, ref),
            const SizedBox(height: SpacingTokens.md),

            // 备份与恢复
            AppTile(
              icon: Icons.folder_outlined,
              iconColor: theme.colorScheme.primary,
              title: '备份与恢复',
              subtitle: '导出或恢复学习数据',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
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
                MaterialPageRoute(
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
                        ref.read(activeSubjectProvider.notifier).state = v;
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

  void _showTtsSpeedPicker(
    BuildContext context,
    WidgetRef ref,
    dynamic settingsRepo,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var speed = settingsRepo.ttsSpeed as double;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '语速调节',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Row(
                      children: [
                        const Text('慢'),
                        Expanded(
                          child: Slider(
                            value: speed,
                            min: 0.1,
                            max: 1.0,
                            divisions: 9,
                            label: speed.toStringAsFixed(1),
                            onChanged: (v) {
                              setState(() => speed = v);
                            },
                          ),
                        ),
                        const Text('快'),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      '当前语速: ${speed.toStringAsFixed(1)}',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          await settingsRepo.setTtsSpeed(speed);
                          ref.invalidate(settingsRepositoryProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('确定'),
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                  ],
                ),
              ),
            );
          },
        ),
        );
      },
    );
  }

  Widget _buildDailyGoalSettings(
    BuildContext context,
    WidgetRef ref,
  ) {
    final poemGoal = ref.watch(dailyPoemGoalProvider);
    final mathGoal = ref.watch(dailyMathGoalProvider);

    return AppTile(
      icon: Icons.flag_outlined,
      iconColor: ColorTokens.poemGold,
      title: '每日目标',
      subtitle: '诗词 $poemGoal 首 · 口算 $mathGoal 题',
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const DailyGoalPage()),
      ),
    );
  }

}
