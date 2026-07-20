// lib/features/profile/notification_settings_page.dart
//
// 层级：features/profile
// 职责：通知设置子页面 — 学习提醒开关 + 时间选择、周报推送开关。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({
    super.key,
    this.notificationService,
  });

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
  }

  String get _timeLabel =>
      '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

  // ============ 学习提醒 ============

  Future<void> _toggleReminder(bool value) async {
    final svc = _notificationService;
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
      final scheduled =
          await svc.scheduleDailyReminder(_reminderHour, _reminderMinute);
      if (!scheduled) {
        _showScheduleFailure('每日提醒设置失败，请稍后重试');
        return;
      }
    } else {
      await svc.cancelDailyReminder();
    }
    if (mounted) setState(() => _reminderEnabled = value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
      helpText: '选择提醒时间',
    );
    if (picked == null || !mounted) return;

    if (_reminderEnabled) {
      final scheduled = await _notificationService.scheduleDailyReminder(
        picked.hour,
        picked.minute,
      );
      if (!scheduled) {
        _showScheduleFailure('提醒时间更新失败，请稍后重试');
        return;
      }
    }

    if (mounted) {
      setState(() {
        _reminderHour = picked.hour;
        _reminderMinute = picked.minute;
      });
    }
  }

  // ============ 学习周报 ============

  Future<void> _toggleWeekly(bool value) async {
    final svc = _notificationService;
    if (value) {
      final granted = await svc.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要通知权限才能开启周报推送')),
          );
        }
        return;
      }
      final scheduled = await svc.scheduleWeeklyReport();
      if (!scheduled) {
        _showScheduleFailure('周报推送设置失败，请稍后重试');
        return;
      }
    } else {
      await svc.cancelWeeklyReport();
    }
    if (mounted) setState(() => _weeklyEnabled = value);
  }

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
          children: [
            // ============ 学习提醒 ============
            ColoredCard(
              color: theme.colorScheme.secondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        color: theme.colorScheme.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Text(
                          '每日学习提醒',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch(
                        value: _reminderEnabled,
                        onChanged: _toggleReminder,
                      ),
                    ],
                  ),
                  Text(
                    '每天定时推送通知，提醒孩子学习诗词和口算',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_reminderEnabled) ...[
                    const SizedBox(height: SpacingTokens.md),
                    InkWell(
                      borderRadius:
                          BorderRadius.circular(SpacingTokens.radiusMedium),
                      onTap: _pickTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.md,
                          vertical: SpacingTokens.sm,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            SpacingTokens.radiusSmall,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 18,
                              color: theme.colorScheme.secondary,
                            ),
                            const SizedBox(width: SpacingTokens.sm),
                            Text(
                              '提醒时间：$_timeLabel',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const Spacer(),
                            Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: theme.colorScheme.secondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // ============ 学习周报 ============
            ColoredCard(
              color: theme.colorScheme.tertiary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.insert_chart_outlined,
                        color: theme.colorScheme.tertiary,
                        size: 20,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Text(
                          '学习周报推送',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch(
                        value: _weeklyEnabled,
                        onChanged: _toggleWeekly,
                      ),
                    ],
                  ),
                  Text(
                    '每周日 18:00 推送本周学习数据汇总通知',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  // 查看周报入口
                  InkWell(
                    borderRadius:
                        BorderRadius.circular(SpacingTokens.radiusMedium),
                    onTap: () => context.push(AppRoutes.weeklyReport),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.md,
                        vertical: SpacingTokens.sm,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                          SpacingTokens.radiusSmall,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.assessment_outlined,
                            size: 18,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: SpacingTokens.sm),
                          Text(
                            '查看本周学习周报',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.tertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.xl),

            // ============ 说明 ============
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
              child: Text(
                '提示：如果通知无法开启，请前往系统设置 → 应用 → 韵算 → 通知，手动开启通知权限。',
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
