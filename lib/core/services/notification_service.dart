// lib/core/services/notification_service.dart
//
// 层级：core/services
// 职责：本地通知服务 — 初始化通知插件、调度每日学习提醒。
//       仅使用 inexactAllowWhileIdle 模式，不需要 SCHEDULE_EXACT_ALARM 权限。

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

typedef LocalTimeZoneIdentifierResolver = Future<String> Function();

Future<String> _resolveLocalTimeZoneIdentifier() async {
  final timeZone = await FlutterTimezone.getLocalTimezone();
  return timeZone.identifier;
}

/// 每日学习提醒通知服务。
class NotificationService {
  NotificationService._({
    FlutterLocalNotificationsPlugin? plugin,
    LocalTimeZoneIdentifierResolver? localTimeZoneIdentifierResolver,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _localTimeZoneIdentifierResolver =
            localTimeZoneIdentifierResolver ?? _resolveLocalTimeZoneIdentifier;

  @visibleForTesting
  NotificationService.forTesting({
    required FlutterLocalNotificationsPlugin plugin,
    required LocalTimeZoneIdentifierResolver localTimeZoneIdentifierResolver,
  })  : _plugin = plugin,
        _localTimeZoneIdentifierResolver = localTimeZoneIdentifierResolver;

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin;
  final LocalTimeZoneIdentifierResolver _localTimeZoneIdentifierResolver;

  // ============ Hive 持久化键 ============

  static const String _keyReminderEnabled = 'reminder_enabled';
  static const String _keyReminderHour = 'reminder_hour';
  static const String _keyReminderMinute = 'reminder_minute';

  static const int _notificationId = 1001;
  static const int _weeklyReportId = 1002;
  static const String _channelId = 'daily_reminder';
  static const String _channelName = '每日学习提醒';
  static const String _channelDescription = '每天定时提醒学习诗词和口算';

  static const String _weeklyChannelId = 'weekly_report';
  static const String _weeklyChannelName = '每周学习周报';
  static const String _weeklyChannelDescription = '每周日推送本周学习数据汇总';

  static const String _keyWeeklyEnabled = 'weekly_report_enabled';

  // ============ 鼓励文案池 ============

  static const _titles = [
    '📚 今天的诗词在等你',
    '🧮 该练口算啦',
    '🌟 每天进步一点点',
    '✨ 学习时间到',
    '🎯 坚持就是胜利',
  ];

  static const _bodies = [
    '读一首诗，做几道题，今天也要加油哦！',
    '古诗背了吗？口算练了吗？快来打卡吧！',
    '坚持学习的你最棒了，快来看看今天的任务！',
    '每天读诗算数，慢慢来，不着急 ❤️',
    '新的一天，新的知识在等你探索！',
  ];

  /// 初始化通知插件。应用启动时调用一次。
  Future<void> initialize() async {
    tz.initializeTimeZones();
    final timeZoneIdentifier = await _localTimeZoneIdentifierResolver();
    tz.setLocalLocation(tz.getLocation(timeZoneIdentifier));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings);

    // 如果之前已开启提醒，重新调度（应用重启后恢复）
    if (isReminderEnabled) {
      final scheduled =
          await scheduleDailyReminder(reminderHour, reminderMinute);
      if (!scheduled) {
        await HiveBoxes.settings.put(_keyReminderEnabled, false);
      }
    }

    // 恢复周报通知
    if (isWeeklyReportEnabled) {
      final scheduled = await scheduleWeeklyReport();
      if (!scheduled) {
        await HiveBoxes.settings.put(_keyWeeklyEnabled, false);
      }
    }
  }

  // ============ 设置存取 ============

  /// 提醒是否已开启。
  bool get isReminderEnabled =>
      HiveBoxes.settings.get(_keyReminderEnabled, defaultValue: false) as bool;

  /// 提醒小时（24h 制），默认 18:00。
  int get reminderHour =>
      HiveBoxes.settings.get(_keyReminderHour, defaultValue: 18) as int;

  /// 提醒分钟，默认 00。
  int get reminderMinute =>
      HiveBoxes.settings.get(_keyReminderMinute, defaultValue: 0) as int;

  // ============ 权限请求 ============

  /// 请求通知权限（Android 13+ / iOS）。
  /// 返回是否已授权。
  Future<bool> requestPermission() async {
    // Android
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    // iOS / macOS
    final darwin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (darwin != null) {
      final granted = await darwin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  // ============ 调度 ============

  /// 开启并调度每日提醒。只有系统调度成功后才持久化设置。
  Future<bool> scheduleDailyReminder(int hour, int minute) async {
    // 选一条随机文案（基于日期做伪随机，每天不同）
    final dayIndex = DateTime.now().day;
    final title = _titles[dayIndex % _titles.length];
    final body = _bodies[dayIndex % _bodies.length];

    // 计算下一次触发时间
    final scheduledDate = _nextInstanceOfTime(hour, minute);

    try {
      await _plugin.zonedSchedule(
        _notificationId,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } on Exception catch (error) {
      AppLogger.e(
        '调度每日提醒失败',
        tag: 'Notify',
        error: error,
      );
      return false;
    }

    await HiveBoxes.settings.put(_keyReminderHour, hour);
    await HiveBoxes.settings.put(_keyReminderMinute, minute);
    await HiveBoxes.settings.put(_keyReminderEnabled, true);
    return true;
  }

  /// 关闭每日提醒。
  Future<void> cancelDailyReminder() async {
    await _plugin.cancel(_notificationId);
    await HiveBoxes.settings.put(_keyReminderEnabled, false);
  }

  /// 计算指定时间的下一次触发 TZDateTime。
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // 如果今天的时间已过，推到明天
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  // ============ 周报推送 ============

  /// 周报是否已开启。
  bool get isWeeklyReportEnabled =>
      HiveBoxes.settings.get(_keyWeeklyEnabled, defaultValue: false) as bool;

  /// 开启周报推送（每周日 18:00）。只有系统调度成功后才持久化设置。
  Future<bool> scheduleWeeklyReport() async {
    final scheduledDate = _nextSunday(18, 0);

    try {
      await _plugin.zonedSchedule(
        _weeklyReportId,
        '📊 本周学习周报',
        '来看看这周学了多少诗词、做了多少口算吧！',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _weeklyChannelId,
            _weeklyChannelName,
            channelDescription: _weeklyChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } on Exception catch (error) {
      AppLogger.e(
        '调度周报通知失败',
        tag: 'Notify',
        error: error,
      );
      return false;
    }

    await HiveBoxes.settings.put(_keyWeeklyEnabled, true);
    return true;
  }

  /// 关闭周报推送。
  Future<void> cancelWeeklyReport() async {
    await _plugin.cancel(_weeklyReportId);
    await HiveBoxes.settings.put(_keyWeeklyEnabled, false);
  }

  /// 计算下一个周日指定时间的 TZDateTime。
  tz.TZDateTime _nextSunday(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var date = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // 找到下一个周日
    while (date.weekday != DateTime.sunday || date.isBefore(now)) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }
}
