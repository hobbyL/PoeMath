// lib/features/profile/settings_page.dart
//
// 层级：features/profile
// 职责：应用设置页 — 主题、音频、显示等设置项逐行展示。

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:poemath/core/config/app_config.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

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
              subtitle: settingsRepo.hapticEnabled ? '已开启' : '已关闭',
              trailing: Switch(
                value: settingsRepo.hapticEnabled,
                onChanged: (v) async {
                  await settingsRepo.setHapticEnabled(v);
                  ref.invalidate(settingsRepositoryProvider);
                },
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 数据备份
            AppTile(
              icon: Icons.cloud_upload_outlined,
              iconColor: theme.colorScheme.primary,
              title: '数据备份',
              subtitle: '导出学习数据',
              onTap: () => _exportBackup(context, ref),
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 数据恢复
            AppTile(
              icon: Icons.cloud_download_outlined,
              iconColor: theme.colorScheme.secondary,
              title: '数据恢复',
              subtitle: '从备份文件恢复',
              onTap: () => _importBackup(context, ref),
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

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final backup = ref.read(backupServiceProvider);
      final filePath = await backup.exportToFile();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(filePath)]),
      );
    } on Exception catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('备份失败: $e')),
      );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final scaffold = ScaffoldMessenger.of(context);

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数据恢复'),
        content: const Text('恢复将覆盖当前所有学习数据，此操作不可撤销。\n\n确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final backup = ref.read(backupServiceProvider);
      final count = await backup.restoreFromFile(filePath);

      scaffold.showSnackBar(
        SnackBar(content: Text('恢复成功，共恢复 $count 条记录')),
      );
    } on FormatException catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复失败: ${e.message}')),
      );
    } on Exception catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复失败: $e')),
      );
    }
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
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: StatefulBuilder(
          builder: (context, setState) {
            var speed = settingsRepo.ttsSpeed as double;
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

}
