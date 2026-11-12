// lib/core/services/notification_service.dart
//
// 层级：core/services
// 职责：本地通知服务 — 初始化通知插件、调度每日学习提醒。
//       获得准时提醒权限时使用精确调度，否则保留系统允许延后的提醒。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// 当前设备的通知投递能力。排定闹钟成功不等于系统允许显示通知。
@immutable
class NotificationDeliveryStatus {
  const NotificationDeliveryStatus({
    this.notificationsEnabled = true,
    this.dailyReminderChannelEnabled = true,
    this.weeklyReportChannelEnabled = true,
    this.dailyReminderBadgeEnabled = true,
    this.weeklyReportBadgeEnabled = true,
    this.exactAlarmsEnabled,
  });

  final bool notificationsEnabled;
  final bool dailyReminderChannelEnabled;
  final bool weeklyReportChannelEnabled;
  final bool dailyReminderBadgeEnabled;
  final bool weeklyReportBadgeEnabled;

  /// 非 Android 平台为 null；Android 12 以下无需特殊授权，插件返回 true。
  final bool? exactAlarmsEnabled;

  bool get canDeliverDailyReminder =>
      notificationsEnabled && dailyReminderChannelEnabled;

  bool get canDeliverWeeklyReport =>
      notificationsEnabled && weeklyReportChannelEnabled;
}

/// 每日学习提醒通知服务。
class NotificationService {
  NotificationService._({
    FlutterLocalNotificationsPlugin? plugin,
    LocalTimeZoneIdentifierResolver? localTimeZoneIdentifierResolver,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _localTimeZoneIdentifierResolver =
           localTimeZoneIdentifierResolver ?? _resolveLocalTimeZoneIdentifier;

  @visibleForTesting
  NotificationService.forTesting({
    required this._plugin,
    required this._localTimeZoneIdentifierResolver,
    this.onNotificationTap,
  });

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin;
  final LocalTimeZoneIdentifierResolver _localTimeZoneIdentifierResolver;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _lastReconciliationSucceeded = true;
  bool? _lastExactAlarmCapability;

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

  // ============ 降级标记（不进备份白名单） ============
  // 语义是「本机这次调度失败了」：换机后由新设备自己重新判定，
  // 迁移过来只会在新设备上弹出错误的告警，因此不入白名单。

  static const String _keyReminderDegraded = 'reminder_degraded';
  static const String _keyWeeklyDegraded = 'weekly_report_degraded';

  static const int _notificationId = 1001;
  static const int _weeklyReportId = 1002;
  static const int _testNotificationId = 1004;
  static const _settingsChannel = MethodChannel(
    'com.poemath.app/notifications',
  );
  static const String _channelId = 'daily_reminder';
  static const String _channelName = '每日学习提醒';
  static const String _channelDescription = '每天定时提醒学习诗词和口算';

  static const String _weeklyChannelId = 'weekly_report';
  static const String _weeklyChannelName = '每周学习周报';
  static const String _weeklyChannelDescription = '每周日推送本周学习数据汇总';

  static const String _keyWeeklyEnabled = 'weekly_report_enabled';

  static const _dailyNotificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      channelShowBadge: true,
      number: 1,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _weeklyNotificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _weeklyChannelId,
      _weeklyChannelName,
      channelDescription: _weeklyChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      channelShowBadge: true,
      number: 1,
    ),
    iOS: DarwinNotificationDetails(),
  );

  // ============ 通知载荷契约 ============

  /// 每日提醒通知的点击 payload（跳转复习页）。
  static const String payloadDailyReminder = 'daily_reminder';

  /// 周报通知的点击 payload（跳转学习周报）。
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
        AppLogger.e('初始化通知服务失败，无法应用恢复设置', tag: 'Notify', error: error);
        return false;
      }
    }
    return _reconcileStoredSchedules();
  }

  Future<bool> _reconcileStoredSchedules() async {
    var succeeded = true;

    // 调度失败**不得**改写用户开关。旧实现在这里写 enabled=false，
    // 用户明明开着提醒，只是系统调度临时失败（免打扰、权限被系统回收、
    // 厂商 ROM 限制），却被静默改写成「用户关掉了」，且不再重试。
    // 现在只记录一个独立的降级标记供设置页提示，用户开关保持不变。
    if (isReminderEnabled) {
      final scheduled = await _scheduleDailyReminder(
        reminderHour,
        reminderMinute,
      );
      if (!scheduled) {
        await _markReminderDegraded(true);
        succeeded = false;
      } else {
        await _markReminderDegraded(false);
      }
    } else {
      try {
        await cancelDailyReminder();
      } on Exception catch (error) {
        AppLogger.e('取消每日提醒失败', tag: 'Notify', error: error);
        succeeded = false;
      }
    }

    if (isWeeklyReportEnabled) {
      final scheduled = await _scheduleWeeklyReport();
      if (!scheduled) {
        await _markWeeklyDegraded(true);
        succeeded = false;
      } else {
        await _markWeeklyDegraded(false);
      }
    } else {
      try {
        await cancelWeeklyReport();
      } on Exception catch (error) {
        AppLogger.e('取消周报通知失败', tag: 'Notify', error: error);
        succeeded = false;
      }
    }

    return succeeded;
  }

  /// 记录/清除「提醒已开启但系统未能调度」的降级标记。
  Future<void> _markReminderDegraded(bool degraded) async {
    await HiveBoxes.settings.put(_keyReminderDegraded, degraded);
  }

  /// 记录/清除周报的降级标记。
  Future<void> _markWeeklyDegraded(bool degraded) async {
    await HiveBoxes.settings.put(_keyWeeklyDegraded, degraded);
  }

  // ============ 设置存取 ============

  /// 提醒是否已开启。
  bool get isReminderEnabled =>
      HiveBoxes.settings.get(_keyReminderEnabled, defaultValue: false) as bool;

  /// 提醒小时（24h 制），默认 18:00。
  int get reminderHour {
    final value = HiveBoxes.settings.get(_keyReminderHour);
    return value is int && value >= 0 && value <= 23 ? value : 18;
  }

  /// 提醒分钟，默认 00。
  int get reminderMinute {
    final value = HiveBoxes.settings.get(_keyReminderMinute);
    return value is int && value >= 0 && value <= 59 ? value : 0;
  }

  /// 提醒已开启但系统未能调度（权限被回收、免打扰、厂商 ROM 限制等）。
  ///
  /// 与 [isReminderEnabled] 正交：这个为 true 表示**用户没关**提醒，
  /// 只是这台设备这次没能排上，设置页据此提示「提醒未能生效」。
  bool get isReminderDegraded =>
      HiveBoxes.settings.get(_keyReminderDegraded, defaultValue: false) as bool;

  bool get isWeeklyReportDegraded =>
      HiveBoxes.settings.get(_keyWeeklyDegraded, defaultValue: false) as bool;

  // ============ 权限请求 ============

  /// 读取系统实际权限与已有通知通道，进入设置页及从系统设置返回时调用。
  Future<NotificationDeliveryStatus> getDeliveryStatus() async {
    await initialize();
    final status = await _readDeliveryStatus();
    final precisionChanged =
        _lastExactAlarmCapability != status.exactAlarmsEnabled &&
        (isReminderEnabled || isWeeklyReportEnabled);
    final deliveryRecovered =
        (isReminderEnabled && isReminderDegraded && status.canDeliverDailyReminder) ||
        (isWeeklyReportEnabled && isWeeklyReportDegraded && status.canDeliverWeeklyReport);
    _lastExactAlarmCapability = status.exactAlarmsEnabled;
    // 系统授权会让家长区锁定并销毁旧页面；重新进入时也能恢复已有提醒。
    if (status.exactAlarmsEnabled != null &&
        (precisionChanged || deliveryRecovered)) {
      await _reconcileStoredSchedules();
    }
    return status;
  }

  Future<NotificationDeliveryStatus> _readDeliveryStatus() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled() ?? true;
      final channels = await android.getNotificationChannels() ?? [];
      var dailyEnabled = true;
      var weeklyEnabled = true;
      var dailyBadgeEnabled = true;
      var weeklyBadgeEnabled = true;
      // 通道尚未创建时使用应用的默认配置；已有通道须尊重用户的系统设置。
      for (final channel in channels) {
        if (channel.id == _channelId) {
          dailyEnabled = channel.importance != Importance.none;
          dailyBadgeEnabled = channel.showBadge;
        } else if (channel.id == _weeklyChannelId) {
          weeklyEnabled = channel.importance != Importance.none;
          weeklyBadgeEnabled = channel.showBadge;
        }
      }
      return NotificationDeliveryStatus(
        notificationsEnabled: enabled,
        dailyReminderChannelEnabled: dailyEnabled,
        weeklyReportChannelEnabled: weeklyEnabled,
        dailyReminderBadgeEnabled: dailyBadgeEnabled,
        weeklyReportBadgeEnabled: weeklyBadgeEnabled,
        exactAlarmsEnabled:
            await android.canScheduleExactNotifications() ?? false,
      );
    }

    return const NotificationDeliveryStatus();
  }

  /// 请求通知权限（Android 13+ / iOS）。
  /// 返回是否已授权。
  Future<bool> requestPermission() async {
    await initialize();
    // Android
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      if (granted != null) return granted;
      // Android 12 及以下没有运行时通知权限，插件返回 null。
      // 旧实现把 null 当 false，导致这些设备「开启提醒」永远失败。
      // 此时应用通知是被系统整体开关控制的，查实际状态才是准的。
      return await android.areNotificationsEnabled() ?? true;
    }

    // iOS / macOS
    final darwin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
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

  /// 仅在用户点击「准时提醒」时请求 Android 闹钟权限，不在启动时弹出。
  Future<bool> requestExactAlarmPermission() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    final granted = await android.requestExactAlarmsPermission() ??
        await android.canScheduleExactNotifications() ??
        false;
    // 只重放已保存的用户开关，不依赖授权返回时页面仍然存活。
    if (granted) await reconcileWithStoredSettings();
    return granted;
  }

  /// 打开本应用的系统通知设置，由用户检查通知开关与角标。
  Future<bool> openSystemNotificationSettings() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await _settingsChannel.invokeMethod<bool>(
          'openNotificationSettings',
        ) ??
        false;
  }

  /// 立即投递到每日提醒的同一通道，不修改提醒设置或后续定时通知。
  Future<bool> sendTestNotification() async {
    try {
      await initialize();
      if (!(await _readDeliveryStatus()).canDeliverDailyReminder) return false;
      await _plugin.show(
        _testNotificationId,
        '🔔 韵算通知测试',
        '通知已送达。返回桌面可查看应用角标，打开韵算后自动清除。',
        _dailyNotificationDetails,
      );
      if (_plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >() !=
          null) {
        // notify() 可空成功；确认系统中实际存在这条通知后再反馈已发送。
        for (var attempt = 0; attempt < 5; attempt++) {
          final active = await _plugin.getActiveNotifications();
          if (active.any(
            (notification) => notification.id == _testNotificationId,
          )) {
            return true;
          }
          if (attempt < 4) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        return false;
      }
      return true;
    } on Exception catch (error) {
      AppLogger.e('发送测试通知失败', tag: 'Notify', error: error);
      return false;
    }
  }

  // ============ 调度 ============

  /// 开启并调度每日提醒。只有系统调度成功后才持久化设置。
  Future<bool> scheduleDailyReminder(int hour, int minute) async {
    try {
      await initialize();
    } on Exception catch (error) {
      AppLogger.e('初始化通知服务失败，无法设置每日提醒', tag: 'Notify', error: error);
      return false;
    }
    return _scheduleDailyReminder(hour, minute);
  }

  // 初始化恢复直接调用已初始化插件的内部调度，避免等待自身 initialize。
  Future<bool> _scheduleDailyReminder(int hour, int minute) async {
    // 选一条随机文案（基于日期做伪随机，每天不同）
    final dayIndex = DateTime.now().day;
    final title = _titles[dayIndex % _titles.length];
    final body = _bodies[dayIndex % _bodies.length];

    // 计算下一次触发时间
    final scheduledDate = _nextInstanceOfTime(hour, minute);

    try {
      final status = await _readDeliveryStatus();
      _lastExactAlarmCapability = status.exactAlarmsEnabled;
      if (!status.canDeliverDailyReminder) return false;
      await _zonedSchedule(
        id: _notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        details: _dailyNotificationDetails,
        exactAlarmsEnabled: status.exactAlarmsEnabled == true,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payloadDailyReminder,
      );
    } on Exception catch (error) {
      AppLogger.e('调度每日提醒失败', tag: 'Notify', error: error);
      return false;
    }

    await HiveBoxes.settings.putAll({
      _keyReminderHour: hour,
      _keyReminderMinute: minute,
      _keyReminderEnabled: true,
      _keyReminderDegraded: false,
    });
    return true;
  }

  /// 关闭每日提醒。
  Future<void> cancelDailyReminder() async {
    await _plugin.cancel(_notificationId);
    await HiveBoxes.settings.putAll({
      _keyReminderEnabled: false,
      _keyReminderDegraded: false,
    });
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
    // 如果今天的时间已过，推到明天。
    // 用构造函数按日历加一天，而非 `add(Duration(days: 1))`：后者是绝对
    // 时长，跨夏令时切换日会整体偏移一小时（03:00 漂成 02:00 或 04:00）。
    if (scheduled.isBefore(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  // ============ 周报推送 ============

  /// 周报是否已开启。
  bool get isWeeklyReportEnabled =>
      HiveBoxes.settings.get(_keyWeeklyEnabled, defaultValue: false) as bool;

  /// 开启周报推送（每周日 18:00）。只有系统调度成功后才持久化设置。
  Future<bool> scheduleWeeklyReport() async {
    try {
      await initialize();
    } on Exception catch (error) {
      AppLogger.e('初始化通知服务失败，无法设置周报', tag: 'Notify', error: error);
      return false;
    }
    return _scheduleWeeklyReport();
  }

  Future<bool> _scheduleWeeklyReport() async {
    final scheduledDate = _nextSunday(18, 0);

    try {
      final status = await _readDeliveryStatus();
      _lastExactAlarmCapability = status.exactAlarmsEnabled;
      if (!status.canDeliverWeeklyReport) return false;
      await _zonedSchedule(
        id: _weeklyReportId,
        title: '📊 本周学习周报',
        body: '来看看这周学了多少诗词、做了多少口算吧！',
        scheduledDate: scheduledDate,
        details: _weeklyNotificationDetails,
        exactAlarmsEnabled: status.exactAlarmsEnabled == true,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: payloadWeeklyReport,
      );
    } on Exception catch (error) {
      AppLogger.e('调度周报通知失败', tag: 'Notify', error: error);
      return false;
    }

    await HiveBoxes.settings.putAll({
      _keyWeeklyEnabled: true,
      _keyWeeklyDegraded: false,
    });
    return true;
  }

  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required bool exactAlarmsEnabled,
    required DateTimeComponents matchDateTimeComponents,
    required String payload,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: exactAlarmsEnabled
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    } on PlatformException catch (error) {
      // 权限可能在查询后、提交前被系统回收；只对此错误降级重试。
      if (!exactAlarmsEnabled || error.code != 'exact_alarms_not_permitted') {
        rethrow;
      }
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    }
  }

  /// 关闭周报推送。
  Future<void> cancelWeeklyReport() async {
    await _plugin.cancel(_weeklyReportId);
    await HiveBoxes.settings.putAll({
      _keyWeeklyEnabled: false,
      _keyWeeklyDegraded: false,
    });
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
    // 找到下一个周日。
    // 同样按日历天数递增构造，避免 `add(Duration(days: 1))` 在夏令时切换日
    // 把 18:00 漂成 17:00 或 19:00。`d + n` 允许 n 超过当月天数，
    // TZDateTime 会归一化到正确的月份。
    var dayOffset = 0;
    while (date.weekday != DateTime.sunday || date.isBefore(now)) {
      dayOffset++;
      date = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + dayOffset,
        hour,
        minute,
      );
    }
    return date;
  }
}
