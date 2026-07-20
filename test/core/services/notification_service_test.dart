import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/hive_test_helper.dart';

class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(tz.TZDateTime.utc(2026));
    registerFallbackValue(const NotificationDetails());
  });

  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    tz.setLocalLocation(tz.UTC);
    await tearDownHiveForTesting();
  });

  test('初始化时在通知插件之前设置设备本地时区', () async {
    final plugin = _MockNotificationsPlugin();
    var localTimeZoneWasConfigured = false;
    when(() => plugin.initialize(any())).thenAnswer((_) async {
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
    verify(() => plugin.initialize(any())).called(1);
  });

  test('设备返回无效时区时停止通知初始化并抛出明确错误', () async {
    final plugin = _MockNotificationsPlugin();
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Invalid/TimeZone',
    );

    await expectLater(
      service.initialize(),
      throwsA(isA<tz.LocationNotFoundException>()),
    );
    verifyNever(() => plugin.initialize(any()));
  });

  test('每日提醒调度失败时返回 false 且不写入开启状态和新时间', () async {
    final plugin = _MockNotificationsPlugin();
    when(() => plugin.initialize(any())).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      ),
    ).thenThrow(Exception('schedule failed'));
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );
    await service.initialize();

    final scheduled = await service.scheduleDailyReminder(7, 30);

    expect(scheduled, isFalse);
    expect(service.isReminderEnabled, isFalse);
    expect(service.reminderHour, 18);
    expect(service.reminderMinute, 0);
    verifyNever(() => plugin.cancel(any()));
  });

  test('每日提醒调度成功后才写入开启状态和时间', () async {
    final plugin = _MockNotificationsPlugin();
    when(() => plugin.initialize(any())).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
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
    final plugin = _MockNotificationsPlugin();
    when(() => plugin.initialize(any())).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
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
    final plugin = _MockNotificationsPlugin();
    when(() => plugin.initialize(any())).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      ),
    ).thenThrow(Exception('schedule failed'));
    final service = NotificationService.forTesting(
      plugin: plugin,
      localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
    );

    await service.initialize();

    expect(service.isReminderEnabled, isFalse);
  });
}
