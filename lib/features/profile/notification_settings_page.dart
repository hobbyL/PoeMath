// lib/features/profile/notification_settings_page.dart
//
// 层级：features/profile
// 职责：通知设置子页面 — 学习提醒开关 + 时间选择、周报推送开关。

import 'dart:async';

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

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  late bool _reminderEnabled;
  late int _reminderHour;
  late int _reminderMinute;
  late bool _weeklyEnabled;
  late bool _weeklyDegraded;
  bool _busy = false;
  NotificationDeliveryStatus? _deliveryStatus;
  bool _statusError = false;

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
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshDeliveryStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      unawaited(_refreshDeliveryStatus());
    }
  }

  Future<void> _refreshDeliveryStatus() => _save(() async {
    try {
      final status = await _notificationService.getDeliveryStatus();
      if (!mounted) return;
      setState(() {
        _deliveryStatus = status;
        _statusError = false;
        _reminderDegraded = _notificationService.isReminderDegraded;
        _weeklyDegraded = _notificationService.isWeeklyReportDegraded;
      });
    } on Object catch (error, stack) {
      AppLogger.e('读取通知状态失败', tag: 'Notify', error: error, stackTrace: stack);
      if (!mounted) return;
      setState(() => _statusError = true);
    }
  }, '读取通知状态失败，请稍后重试', refreshStatus: false);

  String get _timeLabel =>
      '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

  // ============ 学习提醒 ============

  Future<void> _save(
    Future<void> Function() action,
    String failure, {
    bool refreshStatus = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error, stack) {
      AppLogger.e('更新通知设置失败', tag: 'Notify', error: error, stackTrace: stack);
      _showMessage(failure);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (refreshStatus) unawaited(_refreshDeliveryStatus());
      }
    }
  }

  Future<void> _openSystemNotificationSettings() => _save(() async {
    if (!await _notificationService.openSystemNotificationSettings()) {
      _showMessage('请前往系统设置 → 韵算 → 通知，开启通知和角标');
    }
  }, '打开系统通知设置失败，请手动前往系统设置');

  Future<void> _requestExactAlarmPermission() => _save(() async {
    final svc = _notificationService;
    final granted = await svc.requestExactAlarmPermission();
    if (!mounted) return;
    if (!granted) {
      _showMessage('准时提醒未开启，系统可能延后通知');
      return;
    }
    final degraded = (svc.isReminderEnabled && svc.isReminderDegraded) ||
        (svc.isWeeklyReportEnabled && svc.isWeeklyReportDegraded);
    _showMessage(degraded
        ? '准时提醒权限已开启，但提醒未能生效，请检查系统通知设置'
        : '已开启准时提醒');
  }, '开启准时提醒失败，请稍后重试');

  Future<void> _sendTestNotification() => _save(() async {
    final granted = await _notificationService.requestPermission();
    if (!mounted) return;
    if (!granted) {
      _showMessage('需要通知权限才能发送测试通知');
      return;
    }
    final sent = await _notificationService.sendTestNotification();
    _showMessage(sent ? '测试通知已发送，请返回桌面查看通知和角标' : '测试通知未能发送，请检查系统通知与每日提醒通道');
  }, '发送测试通知失败，请稍后重试');

  Future<void> _toggleReminder(bool value) => _save(() async {
    final svc = _notificationService;
    if (value) {
      final granted = await svc.requestPermission();
      if (!mounted) return;
      if (!granted) {
        _showMessage('需要通知权限才能设置提醒');
        return;
      }
      final scheduled = await svc.scheduleDailyReminder(
        _reminderHour,
        _reminderMinute,
      );
      if (!scheduled) {
        _showMessage('每日提醒设置失败，请稍后重试');
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
      _showMessage('提醒时间更新失败，请稍后重试');
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
        _showMessage('需要通知权限才能开启周报推送');
        return;
      }
      if (!await svc.scheduleWeeklyReport()) {
        _showMessage('周报推送设置失败，请稍后重试');
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

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String? get _reminderWarning {
    final status = _deliveryStatus;
    if (status != null) {
      if (!status.notificationsEnabled) {
        return '提醒未能生效：系统通知未开启，请点击「系统通知」开启。';
      }
      if (!status.dailyReminderChannelEnabled) {
        return '提醒未能生效：每日学习提醒通道已关闭，请在系统通知设置中开启。';
      }
      if (!status.dailyReminderBadgeEnabled) {
        return '每日提醒角标已关闭，请在系统通知设置中开启角标。';
      }
    }
    return _reminderDegraded ? '提醒未能生效：请检查系统通知权限或电池优化设置，再来这里重新打开一次。' : null;
  }

  String? get _weeklyWarning {
    final status = _deliveryStatus;
    if (status != null) {
      if (!status.notificationsEnabled) {
        return '周报未能生效：系统通知未开启，请点击「系统通知」开启。';
      }
      if (!status.weeklyReportChannelEnabled) {
        return '周报未能生效：学习周报通道已关闭，请在系统通知设置中开启。';
      }
      if (!status.weeklyReportBadgeEnabled) {
        return '学习周报角标已关闭，请在系统通知设置中开启角标。';
      }
    }
    return _weeklyDegraded ? '周报未能生效：请检查系统通知权限或电池优化设置，再来这里重新打开一次。' : null;
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
                    icon: Icons.settings_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: '系统通知',
                    subtitle: _statusError
                        ? '暂时无法读取通知状态，点击重试'
                        : _deliveryStatus == null
                        ? '正在检查通知权限'
                        : _deliveryStatus!.notificationsEnabled
                        ? '已允许，点击检查通知和角标设置'
                        : '未开启，点击开启通知和角标',
                    onTap: _busy
                        ? null
                        : _statusError
                        ? _refreshDeliveryStatus
                        : _openSystemNotificationSettings,
                  ),
                  if (_deliveryStatus?.exactAlarmsEnabled != null)
                    AppTile(
                      flat: true,
                      icon: Icons.alarm_outlined,
                      iconColor: theme.colorScheme.primary,
                      title: '准时提醒',
                      subtitle: _deliveryStatus!.exactAlarmsEnabled!
                          ? '已开启，按设置时间提醒'
                          : '未开启，系统可能延后通知，点击开启',
                      onTap: _busy ? null : _requestExactAlarmPermission,
                    ),
                  AppTile(
                    flat: true,
                    icon: Icons.notification_add_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: '发送测试通知',
                    subtitle: '立即发送一条提醒，返回桌面查看角标',
                    onTap: _busy ? null : _sendTestNotification,
                  ),
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
                  if (_reminderEnabled && _reminderWarning != null)
                    Text(
                      _reminderWarning!,
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
                  if (_weeklyEnabled && _weeklyWarning != null)
                    Text(
                      _weeklyWarning!,
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
                '应用角标随未查看的通知显示，打开应用后自动清除通知和角标。'
                '角标需在系统设置中开启，并由桌面支持；部分桌面只显示圆点。\n\n'
                '收不到提醒时，先发送测试通知；若测试也收不到，请点击「系统通知」检查。'
                '定时提醒仍未收到时，请检查手机的电池优化或后台运行限制。',
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
