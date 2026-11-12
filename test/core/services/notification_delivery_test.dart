import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/hive_test_helper.dart';

class _Plugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _Android extends Mock implements AndroidFlutterLocalNotificationsPlugin {}

({NotificationService service, _Plugin plugin, _Android android}) _fixture({
  bool notificationsEnabled = true,
  bool exactAlarmsEnabled = false,
  List<AndroidNotificationChannel> channels = const [],
}) {
  final plugin = _Plugin();
  final android = _Android();
  when(
    () => plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >(),
  ).thenReturn(android);
  when(() => android.areNotificationsEnabled())
      .thenAnswer((_) async => notificationsEnabled);
  when(() => android.canScheduleExactNotifications())
      .thenAnswer((_) async => exactAlarmsEnabled);
  when(() => android.getNotificationChannels())
      .thenAnswer((_) async => channels);
  when(
    () => plugin.initialize(
      any(),
      onDidReceiveNotificationResponse: any(
        named: 'onDidReceiveNotificationResponse',
      ),
    ),
  ).thenAnswer((_) async => true);
  when(() => plugin.getNotificationAppLaunchDetails())
      .thenAnswer((_) async => null);
  when(() => plugin.cancel(any())).thenAnswer((_) async {});
  when(() => plugin.getActiveNotifications()).thenAnswer(
    (_) async => [
      const ActiveNotification(id: 1004, channelId: 'daily_reminder'),
    ],
  );
  when(
    () =>
        plugin.show(any(), any(), any(), any(), payload: any(named: 'payload')),
  ).thenAnswer((_) async {});
  when(
    () => plugin.zonedSchedule(
      any(),
      any(),
      any(),
      any(),
      any(),
      androidScheduleMode: any(named: 'androidScheduleMode'),
      matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
      payload: any(named: 'payload'),
    ),
  ).thenAnswer((_) async {});
  return (
    service: NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    ),
    plugin: plugin,
    android: android,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(tz.TZDateTime.utc(2026));
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
    registerFallbackValue(DateTimeComponents.time);
    registerFallbackValue((NotificationResponse _) {});
  });
  setUp(setUpHiveForTesting);
  tearDown(() async {
    tz.setLocalLocation(tz.UTC);
    await tearDownHiveForTesting();
  });

  test('系统通知关闭时恢复失败并保留用户开关，不把排定成功误报为可通知', () async {
    await HiveBoxes.settings.putAll({
      'reminder_enabled': true,
      'weekly_report_enabled': true,
    });
    final fixture = _fixture(notificationsEnabled: false);

    expect(await fixture.service.reconcileWithStoredSettings(), isFalse);
    expect(fixture.service.isReminderEnabled, isTrue);
    expect(fixture.service.isWeeklyReportEnabled, isTrue);
    expect(fixture.service.isReminderDegraded, isTrue);
    expect(fixture.service.isWeeklyReportDegraded, isTrue);
    verifyNever(
      () => fixture.plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
        payload: any(named: 'payload'),
      ),
    );
  });

  test('每日通道被关闭只降级每日提醒，周报仍正常调度', () async {
    await HiveBoxes.settings.putAll({
      'reminder_enabled': true,
      'weekly_report_enabled': true,
    });
    final fixture = _fixture(
      channels: [
        const AndroidNotificationChannel(
          'daily_reminder',
          '每日学习提醒',
          importance: Importance.none,
        ),
        const AndroidNotificationChannel('weekly_report', '每周学习周报'),
      ],
    );

    expect(await fixture.service.reconcileWithStoredSettings(), isFalse);
    expect(fixture.service.isReminderDegraded, isTrue);
    expect(fixture.service.isWeeklyReportDegraded, isFalse);
    verifyNever(
      () => fixture.plugin.zonedSchedule(
        1001,
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
        payload: any(named: 'payload'),
      ),
    );
    verify(
      () => fixture.plugin.zonedSchedule(
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

  for (final exactAllowed in [false, true]) {
    test('${exactAllowed ? '已' : '未'}获得准时提醒权限时使用对应调度模式', () async {
      final fixture = _fixture(exactAlarmsEnabled: exactAllowed);
      await fixture.service.initialize();
      expect(await fixture.service.scheduleDailyReminder(7, 30), isTrue);
      expect(await fixture.service.scheduleWeeklyReport(), isTrue);

      final modes = verify(
        () => fixture.plugin.zonedSchedule(
          any(),
          any(),
          any(),
          any(),
          any(),
          androidScheduleMode: captureAny(named: 'androidScheduleMode'),
          matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
          payload: any(named: 'payload'),
        ),
      ).captured;
      final expected = exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      expect(modes, [expected, expected]);
      verifyNever(() => fixture.android.requestExactAlarmsPermission());
    });
  }

  test('首次直接设置提醒也先完成插件与时区初始化', () async {
    final fixture = _fixture();

    expect(await fixture.service.scheduleDailyReminder(7, 30), isTrue);
    expect(tz.local.name, 'Asia/Shanghai');
    verify(
      () => fixture.plugin.initialize(
        any(),
        onDidReceiveNotificationResponse: any(
          named: 'onDidReceiveNotificationResponse',
        ),
      ),
    ).called(1);
  });

  test('检查后精确权限被回收时降级重试，成功后才保存提醒设置', () async {
    final fixture = _fixture(exactAlarmsEnabled: true);
    when(
      () => fixture.plugin.zonedSchedule(
        1001,
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: NotificationService.payloadDailyReminder,
      ),
    ).thenThrow(PlatformException(code: 'exact_alarms_not_permitted'));

    expect(await fixture.service.scheduleDailyReminder(7, 30), isTrue);
    expect(fixture.service.isReminderEnabled, isTrue);
    expect(fixture.service.reminderHour, 7);
    expect(fixture.service.reminderMinute, 30);
    final modes = verify(
      () => fixture.plugin.zonedSchedule(
        1001,
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: captureAny(named: 'androidScheduleMode'),
        matchDateTimeComponents: DateTimeComponents.time,
        payload: NotificationService.payloadDailyReminder,
      ),
    ).captured;
    expect(modes, [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]);
  });

  for (final enabled in [false, true]) {
    test('旧版 Android 没有运行时授权结果时读取实际通知开关：$enabled', () async {
      final fixture = _fixture(notificationsEnabled: enabled);
      when(() => fixture.android.requestNotificationsPermission())
          .thenAnswer((_) async => null);

      expect(await fixture.service.requestPermission(), enabled);
      verify(() => fixture.android.areNotificationsEnabled()).called(1);
    });
  }

  test('角标关闭不会被误报为通知通道关闭', () async {
    final fixture = _fixture(
      channels: [
        const AndroidNotificationChannel(
          'daily_reminder',
          '每日学习提醒',
          showBadge: false,
        ),
      ],
    );

    final status = await fixture.service.getDeliveryStatus();

    expect(status.canDeliverDailyReminder, isTrue);
    expect(status.canDeliverWeeklyReport, isTrue);
    expect(status.dailyReminderBadgeEnabled, isFalse);
    expect(status.weeklyReportBadgeEnabled, isTrue);
    expect(status.exactAlarmsEnabled, isFalse);
  });

  test('测试通知使用真实提醒通道和角标配置，不改设置或重复提醒', () async {
    final fixture = _fixture();
    await fixture.service.initialize();
    final settingsBefore = HiveBoxes.settings.toMap();
    clearInteractions(fixture.plugin);

    expect(await fixture.service.sendTestNotification(), isTrue);

    final details =
        verify(
              () => fixture.plugin.show(
                1004,
                '🔔 韵算通知测试',
                '通知已送达。返回桌面可查看应用角标，打开韵算后自动清除。',
                captureAny(),
              ),
            ).captured.single
            as NotificationDetails;
    expect(details.android!.channelId, 'daily_reminder');
    expect(details.android!.channelShowBadge, isTrue);
    expect(details.android!.number, 1);
    expect(HiveBoxes.settings.toMap(), settingsBefore);
    verifyNever(() => fixture.plugin.cancel(any()));
    verifyNever(
      () => fixture.plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
        payload: any(named: 'payload'),
      ),
    );
  });

  test('实际通知权限关闭时测试通知返回失败，不把插件空成功当作送达', () async {
    final fixture = _fixture(notificationsEnabled: false);
    await fixture.service.initialize();
    final settingsBefore = HiveBoxes.settings.toMap();

    expect(await fixture.service.sendTestNotification(), isFalse);
    expect(HiveBoxes.settings.toMap(), settingsBefore);
    verifyNever(
      () => fixture.plugin.show(
        any(),
        any(),
        any(),
        any(),
        payload: any(named: 'payload'),
      ),
    );
  });

  test('插件显示调用空成功但系统没有活动通知时不反馈已发送', () async {
    final fixture = _fixture();
    when(() => fixture.plugin.getActiveNotifications())
        .thenAnswer((_) async => []);

    expect(await fixture.service.sendTestNotification(), isFalse);
    verify(() => fixture.plugin.show(1004, any(), any(), any())).called(1);
  });

  test('准时授权由服务恢复已有提醒，不依赖仍存活的设置页面', () async {
    await HiveBoxes.settings.putAll({
      'reminder_enabled': true,
      'weekly_report_enabled': true,
    });
    final fixture = _fixture();
    await fixture.service.initialize();
    clearInteractions(fixture.plugin);
    when(() => fixture.android.requestExactAlarmsPermission()).thenAnswer((_) async {
      when(() => fixture.android.canScheduleExactNotifications())
          .thenAnswer((_) async => true);
      return true;
    });

    expect(await fixture.service.requestExactAlarmPermission(), isTrue);

    for (final id in [1001, 1002]) {
      verify(() => fixture.plugin.zonedSchedule(
        id, any(), any(), any(), any(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
        payload: any(named: 'payload'),
      )).called(1);
    }
    expect(fixture.service.isReminderEnabled, isTrue);
    expect(fixture.service.isWeeklyReportEnabled, isTrue);
  });

  test('系统通知恢复后检查状态会恢复已开启的降级提醒', () async {
    await HiveBoxes.settings.putAll({
      'reminder_enabled': true,
      'weekly_report_enabled': true,
    });
    final fixture = _fixture(notificationsEnabled: false);
    await fixture.service.initialize();
    expect(fixture.service.isReminderDegraded, isTrue);
    expect(fixture.service.isWeeklyReportDegraded, isTrue);
    when(() => fixture.android.areNotificationsEnabled())
        .thenAnswer((_) async => true);

    final status = await fixture.service.getDeliveryStatus();

    expect(status.notificationsEnabled, isTrue);
    expect(fixture.service.isReminderDegraded, isFalse);
    expect(fixture.service.isWeeklyReportDegraded, isFalse);
    expect(fixture.service.isReminderEnabled, isTrue);
    expect(fixture.service.isWeeklyReportEnabled, isTrue);
  });

  test('在外部改变准时权限后检查状态也会更新已有调度模式', () async {
    await HiveBoxes.settings.put('reminder_enabled', true);
    final fixture = _fixture();
    await fixture.service.initialize();
    clearInteractions(fixture.plugin);
    when(() => fixture.android.canScheduleExactNotifications())
        .thenAnswer((_) async => true);

    expect((await fixture.service.getDeliveryStatus()).exactAlarmsEnabled, isTrue);

    verify(() => fixture.plugin.zonedSchedule(
      1001, any(), any(), any(), any(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: NotificationService.payloadDailyReminder,
    )).called(1);
  });
}
