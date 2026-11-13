import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/profile/notification_settings_page.dart';

class _Service extends Mock implements NotificationService {}

_Service _service({
  bool enabled = false,
  NotificationDeliveryStatus status = const NotificationDeliveryStatus(
    exactAlarmsEnabled: false,
  ),
}) {
  final service = _Service();
  when(() => service.isReminderEnabled).thenReturn(enabled);
  when(() => service.reminderHour).thenReturn(18);
  when(() => service.reminderMinute).thenReturn(0);
  when(() => service.isWeeklyReportEnabled).thenReturn(false);
  when(() => service.isReminderDegraded).thenReturn(false);
  when(() => service.isWeeklyReportDegraded).thenReturn(false);
  when(() => service.getDeliveryStatus()).thenAnswer((_) async => status);
  when(() => service.scheduleDailyReminder(18, 0))
      .thenAnswer((_) async => true);
  return service;
}

Future<void> _pump(WidgetTester tester, NotificationService service) async {
  await tester.pumpWidget(
    MaterialApp(home: NotificationSettingsPage(notificationService: service)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('权限等待期间重复点击只请求一次并禁用相关操作', (tester) async {
    final service = _service();
    final permission = Completer<bool>();
    when(() => service.requestPermission())
        .thenAnswer((_) => permission.future);
    await _pump(tester, service);
    final callback = tester
        .widget<Switch>(find.byType(Switch).first)
        .onChanged!;
    callback(true);
    callback(true);
    await tester.pump();
    final disabled = tester.widget<Switch>(find.byType(Switch).first).onChanged;
    permission.complete(true);
    await tester.pumpAndSettle();
    expect(disabled, isNull);
    verify(() => service.requestPermission()).called(1);
    verify(() => service.scheduleDailyReminder(18, 0)).called(1);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('通知权限返回时已离页，不再开启提醒', (tester) async {
    final service = _service();
    final permission = Completer<bool>();
    when(() => service.requestPermission())
        .thenAnswer((_) => permission.future);
    await _pump(tester, service);
    tester.widget<Switch>(find.byType(Switch).first).onChanged!(true);
    await tester.pumpWidget(const SizedBox.shrink());
    permission.complete(true);
    await tester.pumpAndSettle();
    verifyNever(() => service.scheduleDailyReminder(18, 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消提醒平台异常显示失败且可重试', (tester) async {
    final service = _service(enabled: true);
    when(() => service.cancelDailyReminder())
        .thenThrow(PlatformException(code: 'cancel_failed'));
    await _pump(tester, service);
    tester.widget<Switch>(find.byType(Switch).first).onChanged!(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text('每日提醒设置失败，请稍后重试'), findsOneWidget);
    when(() => service.cancelDailyReminder()).thenAnswer((_) async {});
    tester.widget<Switch>(find.byType(Switch).first).onChanged!(false);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    verify(() => service.cancelDailyReminder()).called(2);
  });

  testWidgets('周报调度降级明确提示，关闭成功后移除提示', (tester) async {
    final service = _service();
    when(() => service.isWeeklyReportEnabled).thenReturn(true);
    when(() => service.isWeeklyReportDegraded).thenReturn(true);
    when(() => service.cancelWeeklyReport()).thenAnswer((_) async {});
    await _pump(tester, service);
    expect(find.textContaining('周报未能生效'), findsOneWidget);
    tester.widget<Switch>(find.byType(Switch).last).onChanged!(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('周报未能生效'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    verify(() => service.cancelWeeklyReport()).called(1);
  });

  testWidgets('320dp 双倍字号的通知设置可滚动且时间和周报入口不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: NotificationSettingsPage(
          notificationService: _service(enabled: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('发送测试通知'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('查看本周学习周报'),
      250,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('查看本周学习周报'), findsOneWidget);
    expect(find.textContaining('18:00'), findsWidgets);
  });

  testWidgets('系统实际通知关闭时提示原因，系统设置入口可用', (tester) async {
    final service = _service(
      enabled: true,
      status: const NotificationDeliveryStatus(
        notificationsEnabled: false,
        exactAlarmsEnabled: false,
      ),
    );
    when(() => service.openSystemNotificationSettings())
        .thenAnswer((_) async => true);
    await _pump(tester, service);

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text('未开启，点击开启通知和角标'), findsOneWidget);
    expect(find.textContaining('系统通知未开启'), findsOneWidget);
    await tester.tap(find.text('系统通知'));
    await tester.pumpAndSettle();
    verify(() => service.openSystemNotificationSettings()).called(1);
  });

  testWidgets('准时提醒授权成功后刷新设备状态并保留已有提醒', (tester) async {
    final service = _service(enabled: true);
    var status = const NotificationDeliveryStatus(exactAlarmsEnabled: false);
    when(() => service.getDeliveryStatus()).thenAnswer((_) async => status);
    when(() => service.requestExactAlarmPermission()).thenAnswer((_) async {
      status = const NotificationDeliveryStatus(exactAlarmsEnabled: true);
      return true;
    });
    await _pump(tester, service);
    expect(find.text('未开启，系统可能延后通知，点击开启'), findsOneWidget);
    clearInteractions(service);

    await tester.tap(find.text('准时提醒'));
    await tester.pumpAndSettle();

    verify(() => service.requestExactAlarmPermission()).called(1);
    verify(() => service.getDeliveryStatus()).called(1);
    verifyNever(() => service.reconcileWithStoredSettings());
    expect(find.text('已开启，按设置时间提醒'), findsOneWidget);
    expect(find.text('已开启准时提醒'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('准时授权成功但通知仍关闭时明确提示提醒未生效', (tester) async {
    final service = _service(enabled: true);
    var status = const NotificationDeliveryStatus(
      notificationsEnabled: false,
      exactAlarmsEnabled: false,
    );
    when(() => service.isReminderDegraded).thenReturn(true);
    when(() => service.getDeliveryStatus()).thenAnswer((_) async => status);
    when(() => service.requestExactAlarmPermission()).thenAnswer((_) async {
      status = const NotificationDeliveryStatus(
        notificationsEnabled: false,
        exactAlarmsEnabled: true,
      );
      return true;
    });
    await _pump(tester, service);

    await tester.tap(find.text('准时提醒'));
    await tester.pumpAndSettle();

    expect(find.text('准时提醒权限已开启，但提醒未能生效，请检查系统通知设置'), findsOneWidget);
    expect(find.text('已开启准时提醒'), findsNothing);
    expect(find.textContaining('系统通知未开启'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('不授予准时提醒权限时保留已有提醒并提示可能延后', (tester) async {
    final service = _service(enabled: true);
    when(() => service.requestExactAlarmPermission())
        .thenAnswer((_) async => false);
    await _pump(tester, service);

    await tester.tap(find.text('准时提醒'));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text('准时提醒未开启，系统可能延后通知'), findsOneWidget);
    verifyNever(() => service.reconcileWithStoredSettings());
  });

  testWidgets('测试通知等待授权时禁用重复发送，授权后只发一条', (tester) async {
    final service = _service();
    final permission = Completer<bool>();
    when(() => service.requestPermission())
        .thenAnswer((_) => permission.future);
    when(() => service.sendTestNotification()).thenAnswer((_) async => true);
    await _pump(tester, service);
    final testTile = find.ancestor(
      of: find.text('发送测试通知'),
      matching: find.byType(AppTile),
    );
    final callback = tester.widget<AppTile>(testTile).onTap!;
    callback();
    callback();
    await tester.pump();
    expect(tester.widget<AppTile>(testTile).onTap, isNull);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);

    permission.complete(true);
    await tester.pumpAndSettle();

    verify(() => service.requestPermission()).called(1);
    verify(() => service.sendTestNotification()).called(1);
    verifyNever(() => service.scheduleDailyReminder(18, 0));
    expect(find.text('测试通知已发送，请返回桌面查看通知和角标'), findsOneWidget);
  });

  testWidgets('从系统设置返回后重新读取权限并恢复原有提醒', (tester) async {
    final service = _service(enabled: true);
    var status = const NotificationDeliveryStatus(
      notificationsEnabled: false,
      exactAlarmsEnabled: false,
    );
    var degraded = true;
    when(() => service.isReminderDegraded).thenAnswer((_) => degraded);
    when(() => service.getDeliveryStatus()).thenAnswer((_) async {
      degraded = !status.canDeliverDailyReminder;
      return status;
    });
    await _pump(tester, service);
    expect(find.textContaining('系统通知未开启'), findsOneWidget);
    clearInteractions(service);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    status = const NotificationDeliveryStatus(exactAlarmsEnabled: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    verify(() => service.getDeliveryStatus()).called(1);
    verifyNever(() => service.reconcileWithStoredSettings());
    expect(find.text('已允许，点击检查通知和角标设置'), findsOneWidget);
    expect(find.textContaining('提醒未能生效'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });
}
