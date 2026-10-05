import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/hive_test_helper.dart';

class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

_MockNotificationsPlugin _createPlugin() {
  final plugin = _MockNotificationsPlugin();
  when(() => plugin.cancel(any())).thenAnswer((_) async {});
  // 默认无冷启动通知拉起；需要冷启动场景的测试单独覆盖此 stub。
  when(
    () => plugin.getNotificationAppLaunchDetails(),
  ).thenAnswer((_) async => null);
  return plugin;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(tz.TZDateTime.utc(2026));
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue((NotificationResponse _) {});
  });

  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    tz.setLocalLocation(tz.UTC);
    await tearDownHiveForTesting();
  });

  test('初始化时在通知插件之前设置设备本地时区', () async {
    final plugin = _createPlugin();
    var localTimeZoneWasConfigured = false;
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async {
      localTimeZoneWasConfigured = tz.local.name == 'Asia/Shanghai';
      return true;
    });
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );

    await service.initialize();

    expect(tz.local.name, 'Asia/Shanghai');
    expect(localTimeZoneWasConfigured, isTrue);
    verify(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).called(1);
  });

  test('设备返回无效时区时停止通知初始化并抛出明确错误', () async {
    final plugin = _createPlugin();
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Invalid/TimeZone',
    );

    await expectLater(
      service.initialize(),
      throwsA(isA<tz.LocationNotFoundException>()),
    );
    verifyNever(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    );
  });

  test('每日提醒调度失败时返回 false 且不写入开启状态和新时间', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: any(named: 'payload'),
      ),
    ).thenThrow(Exception('schedule failed'));
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();
    clearInteractions(plugin);

    final scheduled = await service.scheduleDailyReminder(7, 30);

    expect(scheduled, isFalse);
    expect(service.isReminderEnabled, isFalse);
    expect(service.reminderHour, 18);
    expect(service.reminderMinute, 0);
    verifyNever(() => plugin.cancel(any()));
  });

  test('每日提醒调度成功后才写入开启状态和时间', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();

    final scheduled = await service.scheduleDailyReminder(7, 30);

    expect(scheduled, isTrue);
    expect(service.isReminderEnabled, isTrue);
    expect(service.reminderHour, 7);
    expect(service.reminderMinute, 30);
  });

  test('周报调度失败时返回 false 且不写入开启状态', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: any(named: 'payload'),
      ),
    ).thenThrow(Exception('schedule failed'));
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();

    final scheduled = await service.scheduleWeeklyReport();

    expect(scheduled, isFalse);
    expect(service.isWeeklyReportEnabled, isFalse);
  });

  test('启动恢复每日提醒失败时清除失真的开启状态', () async {
    await HiveBoxes.settings.put('reminder_enabled', true);
    await HiveBoxes.settings.put('reminder_hour', 7);
    await HiveBoxes.settings.put('reminder_minute', 30);
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: any(named: 'payload'),
      ),
    ).thenThrow(Exception('schedule failed'));
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );

    await service.initialize();

    expect(service.isReminderEnabled, isFalse);
  });

  test('重复初始化只初始化一次通知插件', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );

    await Future.wait([service.initialize(), service.initialize()]);

    verify(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).called(1);
  });

  test('恢复为关闭状态时取消已有每日提醒和周报', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();
    clearInteractions(plugin);

    final applied = await service.reconcileWithStoredSettings();

    expect(applied, isTrue);
    verify(() => plugin.cancel(1001)).called(1);
    verify(() => plugin.cancel(1002)).called(1);
  });

  test('恢复为开启状态时重新调度每日提醒和周报', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();
    await HiveBoxes.settings.put('reminder_enabled', true);
    await HiveBoxes.settings.put('reminder_hour', 7);
    await HiveBoxes.settings.put('reminder_minute', 30);
    await HiveBoxes.settings.put('weekly_report_enabled', true);
    clearInteractions(plugin);

    final applied = await service.reconcileWithStoredSettings();

    expect(applied, isTrue);
    expect(service.reminderHour, 7);
    expect(service.reminderMinute, 30);
    verify(
      () => plugin.zonedSchedule(
        1001,
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: any(named: 'payload'),
      ),
    ).called(1);
    verify(
      () => plugin.zonedSchedule(
        1002,
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: any(named: 'payload'),
      ),
    ).called(1);
  });

  test('前台点击通知时把 payload 透传给注入的回调，空 payload 不透传', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);

    final receivedPayloads = <String>[];
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
      onNotificationTap: receivedPayloads.add,
    );
    await service.initialize();

    // 取出 initialize 注册的通知点击回调（payload 透传通道）。
    final handler = verify(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            captureAny(named: 'onDidReceiveNotificationResponse'),
      ),
    ).captured.single as DidReceiveNotificationResponseCallback;

    handler(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: NotificationService.payloadDailyReminder,
      ),
    );
    handler(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: NotificationService.payloadWeeklyReport,
      ),
    );
    // 空 payload 静默忽略，不触发跳转。
    handler(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
      ),
    );

    expect(receivedPayloads, [
      NotificationService.payloadDailyReminder,
      NotificationService.payloadWeeklyReport,
    ]);
  });

  test('冷启动由通知拉起时 payload 一次性消费，再次消费返回 null', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
      (_) async => const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: NotificationService.payloadWeeklyReport,
        ),
      ),
    );

    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();

    final first = await service.consumePendingLaunchPayload();
    final second = await service.consumePendingLaunchPayload();

    expect(first, NotificationService.payloadWeeklyReport);
    expect(second, isNull, reason: '冷启动 payload 只消费一次');
  });

  test('非通知冷启动（普通启动）时不产生待消费 payload', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
      (_) async => const NotificationAppLaunchDetails(false),
    );

    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();

    expect(await service.consumePendingLaunchPayload(), isNull);
  });

  test('调度每日提醒与周报时写入点击跳转 payload 常量', () async {
    final plugin = _createPlugin();
    when(
      () => plugin.initialize(
        any(),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});

    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();
    await HiveBoxes.settings.put('reminder_enabled', true);
    await HiveBoxes.settings.put('weekly_report_enabled', true);
    await service.reconcileWithStoredSettings();

    verify(
      () => plugin.zonedSchedule(
        1001,
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: NotificationService.payloadDailyReminder,
      ),
    ).called(1);
    verify(
      () => plugin.zonedSchedule(
        1002,
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: NotificationService.payloadWeeklyReport,
      ),
    ).called(1);
  });
}
