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

/// 通知点击回调：payload 为调度时写入的通知载荷
/// （见 [NotificationService.payloadDailyReminder] 等）。
typedef NotificationTapCallback = void Function(String payload);

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
    this.onNotificationTap,
  })  : _plugin = plugin,
        _localTimeZoneIdentifierResolver = localTimeZoneIdentifierResolver;

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin;
  final LocalTimeZoneIdentifierResolver _localTimeZoneIdentifierResolver;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _lastReconciliationSucceeded = true;

  /// 冷启动（terminated 状态点击通知拉起应用）时捕获的通知载荷。
  ///
  /// 由 [consumePendingLaunchPayload] 消费一次后清空。
  String? _pendingLaunchPayload;

  /// 通知点击回调。service 保持纯 Dart 不依赖路由：前台点击通知时由
  /// `onDidReceiveNotificationResponse` 透传 payload；跳转实现（如
  /// `appRouter.push(AppRoutes.poemReview)`）由 MainShell 启动时注入，
  /// 运行期可更换或置空。
  NotificationTapCallback? onNotificationTap;

  // ============ Hive 持久化键 ============
  // 以下 4 个通知设置 key 已登记备份白名单
  // （backup_service.dart 的 _settingsValueType，14+4=18 个），
  // 新增需要随备份迁移的 key 时必须同步登记，否则换机后不迁移；
  // 指向外部服务或绑定凭据的 key 一律不得入白名单。

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

  // ============ 通知载荷契约 ============

  /// 每日提醒通知的点击 payload（跳转复习页）。
  static const String payloadDailyReminder = 'daily_reminder';

  /// 周报通知的点击 payload（跳转复习页）。
  static const String payloadWeeklyReport = 'weekly_report';

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
  Future<void> initialize() {
    return _initializeFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
      await _initializePlugin();
    } on Exception {
      _initializeFuture = null;
      rethrow;
    }
  }

  Future<void> _initializePlugin() async {
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

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );
    _lastReconciliationSucceeded = await _reconcileStoredSchedules();
    _initialized = true;
    await _capturePendingLaunchPayload();
  }

  /// 前台/后台点击通知：透传 payload 给注入的回调。
  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    onNotificationTap?.call(payload);
  }

  /// 冷启动检查：应用由 terminated 状态被通知点击拉起时，
  /// 记录启动通知的 payload，等待 UI 就绪后由
  /// [consumePendingLaunchPayload] 消费。失败只记日志，不影响初始化。
  Future<void> _capturePendingLaunchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final response = details?.notificationResponse;
      final payload = response?.payload;
      if ((details?.didNotificationLaunchApp ?? false) &&
          payload != null &&
          payload.isNotEmpty) {
        _pendingLaunchPayload = payload;
      }
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '读取通知冷启动载荷失败',
        tag: 'Notify',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 消费冷启动（terminated 状态点击通知拉起）的通知 payload，一次性取走。
  ///
  /// 确保 [initialize] 完成后返回；初始化失败或无载荷返回 null。
  Future<String?> consumePendingLaunchPayload() async {
    try {
      await initialize();
    } on Exception {
      return null;
    }
    final payload = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    return payload;
  }

  /// 根据 Hive 中的设置重新调度或取消设备通知。
  Future<bool> reconcileWithStoredSettings() async {
    if (!_initialized) {
      try {
        await initialize();
        return _lastReconciliationSucceeded;
      } on Exception catch (error) {
        AppLogger.e(
          '初始化通知服务失败，无法应用恢复设置',
          tag: 'Notify',
          error: error,
        );
        return false;
      }
    }
    return _reconcileStoredSchedules();
  }

  Future<bool> _reconcileStoredSchedules() async {
    var succeeded = true;

    if (isReminderEnabled) {
      final scheduled =
          await scheduleDailyReminder(reminderHour, reminderMinute);
      if (!scheduled) {
        await HiveBoxes.settings.put(_keyReminderEnabled, false);
        succeeded = false;
      }
    } else {
      try {
        await cancelDailyReminder();
      } on Exception catch (error) {
        AppLogger.e(
          '取消每日提醒失败',
          tag: 'Notify',
          error: error,
        );
        succeeded = false;
      }
    }

    if (isWeeklyReportEnabled) {
      final scheduled = await scheduleWeeklyReport();
      if (!scheduled) {
        await HiveBoxes.settings.put(_keyWeeklyEnabled, false);
        succeeded = false;
      }
    } else {
      try {
        await cancelWeeklyReport();
      } on Exception catch (error) {
        AppLogger.e(
          '取消周报通知失败',
          tag: 'Notify',
          error: error,
        );
        succeeded = false;
      }
    }

    return succeeded;
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
        payload: payloadDailyReminder,
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
        payload: payloadWeeklyReport,
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
