import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/features/profile/notification_settings_page.dart';

class _Service extends Mock implements NotificationService {}

_Service _service({bool enabled = false}) {
  final service = _Service();
  when(() => service.isReminderEnabled).thenReturn(enabled);
  when(() => service.reminderHour).thenReturn(18);
  when(() => service.reminderMinute).thenReturn(0);
  when(() => service.isWeeklyReportEnabled).thenReturn(false);
  when(() => service.isReminderDegraded).thenReturn(false);
  when(() => service.isWeeklyReportDegraded).thenReturn(false);
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
    await tester.ensureVisible(find.text('查看本周学习周报'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('18:00'), findsWidgets);
  });
}
