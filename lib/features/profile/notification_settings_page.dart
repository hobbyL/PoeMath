// lib/features/profile/notification_settings_page.dart
//
// 层级：features/profile
// 职责：通知设置子页面 — 学习提醒开关 + 时间选择、周报推送开关。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, this.notificationService});

  final NotificationService? notificationService;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late bool _reminderEnabled;
  late int _reminderHour;
  late int _reminderMinute;
  late bool _weeklyEnabled;
  late bool _weeklyDegraded;
  bool _busy = false;

  /// 上次启动恢复时系统未能排上提醒（用户开关仍然是「开」）。
  late bool _reminderDegraded;

  NotificationService get _notificationService =>
      widget.notificationService ?? NotificationService.instance;

  @override
  void initState() {
    super.initState();
    final svc = _notificationService;
    _reminderEnabled = svc.isReminderEnabled;
    _reminderHour = svc.reminderHour;
    _reminderMinute = svc.reminderMinute;
    _weeklyEnabled = svc.isWeeklyReportEnabled;
    _reminderDegraded = svc.isReminderDegraded;
    _weeklyDegraded = svc.isWeeklyReportDegraded;
  }

  String get _timeLabel =>
      '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

  // ============ 学习提醒 ============

  Future<void> _save(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error, stack) {
      AppLogger.e('更新通知设置失败', tag: 'Notify', error: error, stackTrace: stack);
      _showScheduleFailure(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleReminder(bool value) => _save(() async {
    final svc = _notificationService;
    if (value) {
      final granted = await svc.requestPermission();
      if (!mounted) return;
      if (!granted) {
        _showScheduleFailure('需要通知权限才能设置提醒');
        return;
      }
      final scheduled = await svc.scheduleDailyReminder(
        _reminderHour,
        _reminderMinute,
      );
      if (!scheduled) {
        _showScheduleFailure('每日提醒设置失败，请稍后重试');
        return;
      }
    } else {
      await svc.cancelDailyReminder();
    }
    if (mounted) {
      setState(() {
        _reminderEnabled = value;
        _reminderDegraded = false;
      });
    }
  }, '每日提醒设置失败，请稍后重试');

  Future<void> _pickTime() => _save(() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
      helpText: '选择提醒时间',
    );
    if (picked == null || !mounted) return;
    final scheduled = await _notificationService.scheduleDailyReminder(
      picked.hour,
      picked.minute,
    );
    if (!scheduled) {
      _showScheduleFailure('提醒时间更新失败，请稍后重试');
      return;
    }
    if (mounted) {
      setState(() {
        _reminderHour = picked.hour;
        _reminderMinute = picked.minute;
        _reminderDegraded = false;
      });
    }
  }, '提醒时间更新失败，请稍后重试');

  Future<void> _toggleWeekly(bool value) => _save(() async {
    final svc = _notificationService;
    if (value) {
      final granted = await svc.requestPermission();
      if (!mounted) return;
      if (!granted) {
        _showScheduleFailure('需要通知权限才能开启周报推送');
        return;
      }
      if (!await svc.scheduleWeeklyReport()) {
        _showScheduleFailure('周报推送设置失败，请稍后重试');
        return;
      }
    } else {
      await svc.cancelWeeklyReport();
    }
    if (mounted) {
      setState(() {
        _weeklyEnabled = value;
        _weeklyDegraded = false;
      });
    }
  }, '周报推送设置失败，请稍后重试');

  void _showScheduleFailure(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: [
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTile(
                    flat: true,
                    icon: Icons.notifications_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: '每日学习提醒',
                    subtitle: '每天定时推送通知，提醒孩子学习诗词和口算',
                    trailingInTitle: true,
                    trailing: Semantics(
                      label: '每日学习提醒',
                      child: Switch(
                        value: _reminderEnabled,
                        onChanged: _busy ? null : _toggleReminder,
                      ),
                    ),
                  ),
                  if (_reminderEnabled && _reminderDegraded)
                    Text(
                      '提醒未能生效：请检查系统通知权限或电池优化设置，再来这里重新打开一次。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (_reminderEnabled) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    AppTile(
                      flat: true,
                      icon: Icons.access_time,
                      iconColor: theme.colorScheme.primary,
                      title: '提醒时间：$_timeLabel',
                      subtitle: '',
                      trailingIcon: Icons.edit_outlined,
                      onTap: _busy ? null : _pickTime,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTile(
                    flat: true,
                    icon: Icons.insert_chart_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: '学习周报推送',
                    subtitle: '每周日 18:00 推送本周学习数据汇总通知',
                    trailingInTitle: true,
                    trailing: Semantics(
                      label: '学习周报推送',
                      child: Switch(
                        value: _weeklyEnabled,
                        onChanged: _busy ? null : _toggleWeekly,
                      ),
                    ),
                  ),
                  if (_weeklyEnabled && _weeklyDegraded)
                    Text(
                      '周报未能生效：请检查系统通知权限或电池优化设置，再来这里重新打开一次。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: SpacingTokens.sm),
                  AppTile(
                    flat: true,
                    icon: Icons.assessment_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: '查看本周学习周报',
                    subtitle: '',
                    onTap: () => context.push(AppRoutes.weeklyReport),
                  ),
                ],
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: SpacingTokens.md),
              const LinearProgressIndicator(semanticsLabel: '正在更新通知设置'),
            ],
            const SizedBox(height: SpacingTokens.xl),

            // ============ 说明 ============
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
              child: Text(
                '未查看的提醒会显示应用图标角标，打开应用后自动清除通知和角标。'
                '数字角标需系统桌面支持，部分桌面只显示圆点。\n\n'
                '如果通知无法开启，请前往系统设置 → 应用 → 韵算 → 通知，手动开启通知权限。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
