import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:timezone/timezone.dart' as tz;

import '../test/helpers/hive_test_helper.dart';

const _fixtureNotificationIds = {1001, 1002, 1003};

Future<Set<int>> _waitForActiveIds(
  FlutterLocalNotificationsPlugin plugin,
  Set<int> expected, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  Set<int> ids;
  do {
    // 系统可另行生成分组摘要；逐一核对本测试投递的提醒和持续通知。
    ids = (await plugin.getActiveNotifications())
        .where(
          (notification) => _fixtureNotificationIds.contains(notification.id),
        )
        .map((notification) => notification.id!)
        .toSet();
    if (ids.length == expected.length && ids.containsAll(expected)) return ids;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  } while (DateTime.now().isBefore(deadline));
  return ids;
}

// 使用 --dart-define=POEMATH_INTEGRATION_TEST=true，只操作独立测试应用。
// POEMATH_BADGE_WAITING_FOR_PERMISSION 后为测试应用授予通知权限。
// 测试自动打开只读的系统权限设置；POEMATH_BADGE_READY_FOR_RESUME 后按返回。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('打开应用清除未读通知，保留持续通知和后续重复提醒', (tester) async {
    expect(const bool.fromEnvironment('POEMATH_INTEGRATION_TEST'), isTrue);
    final version = await AndroidUpdateInstaller().getCurrentVersion();
    expect(version.packageName, 'com.poemath.app.integration');
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    await tester.runAsync(() async {
      await setUpHiveForTesting();
      final plugin = FlutterLocalNotificationsPlugin();
      try {
        final service = NotificationService.instance;
        await service.initialize();
        final android = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()!;
        debugPrint('POEMATH_BADGE_WAITING_FOR_PERMISSION');
        final permissionDeadline =
            DateTime.now().add(const Duration(seconds: 60));
        while (!(await android.areNotificationsEnabled() ?? false) &&
            DateTime.now().isBefore(permissionDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(await android.areNotificationsEnabled(), isTrue);

        final reminderTime =
            tz.TZDateTime.now(tz.local).add(const Duration(hours: 2));
        expect(
          await service.scheduleDailyReminder(
            reminderTime.hour,
            reminderTime.minute,
          ),
          isTrue,
        );
        expect(await service.scheduleWeeklyReport(), isTrue);
        final settingsBefore = HiveBoxes.settings.toMap();
        final pendingBefore = await plugin.pendingNotificationRequests();
        expect(
          pendingBefore.map((request) => request.id).toSet(),
          {1001, 1002},
        );

        const dailyDetails = NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            '每日学习提醒',
            channelShowBadge: true,
            number: 1,
          ),
        );

        await plugin.show(
          1001,
          '每日学习提醒验收',
          '这是一条未查看的学习提醒',
          dailyDetails,
          payload: NotificationService.payloadDailyReminder,
        );
        await plugin.show(
          1002,
          '每周学习周报验收',
          '这是一条未查看的周报提醒',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'weekly_report',
              '每周学习周报',
              channelShowBadge: true,
              number: 1,
            ),
          ),
          payload: NotificationService.payloadWeeklyReport,
        );
        await plugin.show(
          1003,
          '持续状态验收',
          '打开应用后应保留这条持续通知',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'badge_test_ongoing',
              '角标验收持续通知',
              channelShowBadge: false,
              ongoing: true,
              autoCancel: false,
            ),
          ),
        );
        expect(await _waitForActiveIds(plugin, {1001, 1002, 1003}), {
          1001,
          1002,
          1003,
        });

        // 系统设置返回只触发 onResume，独立覆盖恢复前台而无新 intent 的场景。
        const settingsChannel = MethodChannel('com.poemath.app/app_update');
        await settingsChannel.invokeMethod<void>(
          'openInstallPermissionSettings',
        );
        final backgroundDeadline =
            DateTime.now().add(const Duration(seconds: 5));
        while (WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.paused &&
            DateTime.now().isBefore(backgroundDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          WidgetsBinding.instance.lifecycleState,
          AppLifecycleState.paused,
        );
        debugPrint('POEMATH_BADGE_READY_FOR_RESUME');
        expect(
          await _waitForActiveIds(
            plugin,
            {1003},
            timeout: const Duration(seconds: 60),
          ),
          {1003},
        );
        final pendingAfter = await plugin.pendingNotificationRequests();
        expect(pendingAfter.map((request) => request.id).toSet(), {1001, 1002});
        expect(HiveBoxes.settings.toMap(), settingsBefore);
        debugPrint('POEMATH_BADGE_RESUME_VERIFIED');

        // 先等窗口完全回到前台，再投递“已经打开应用时”的新提醒。
        final foregroundDeadline =
            DateTime.now().add(const Duration(seconds: 5));
        while (WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed &&
            DateTime.now().isBefore(foregroundDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          WidgetsBinding.instance.lifecycleState,
          AppLifecycleState.resumed,
        );
        await Future<void>.delayed(const Duration(seconds: 1));

        await plugin.show(
          1001,
          '前台再次打开验收',
          '再次打开已经在前台的应用也应清除提醒',
          dailyDetails,
          payload: NotificationService.payloadDailyReminder,
        );
        expect(await _waitForActiveIds(plugin, {1001, 1003}), {1001, 1003});
        debugPrint('POEMATH_BADGE_READY_FOR_NEW_INTENT');
        expect(
          await _waitForActiveIds(
            plugin,
            {1003},
            timeout: const Duration(seconds: 60),
          ),
          {1003},
        );
        expect(
          (await plugin.pendingNotificationRequests())
              .map((request) => request.id)
              .toSet(),
          {1001, 1002},
        );
        expect(HiveBoxes.settings.toMap(), settingsBefore);
        debugPrint('POEMATH_BADGE_NEW_INTENT_VERIFIED');
      } finally {
        await plugin.cancelAll();
        await tearDownHiveForTesting();
      }
    });
  });
}
