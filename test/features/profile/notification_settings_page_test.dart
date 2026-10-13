import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/features/profile/notification_settings_page.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  testWidgets('每日提醒调度失败时开关保持关闭并提示失败', (tester) async {
    final service = _MockNotificationService();
    when(() => service.isReminderEnabled).thenReturn(false);
    when(() => service.reminderHour).thenReturn(18);
    when(() => service.reminderMinute).thenReturn(0);
    when(() => service.isWeeklyReportEnabled).thenReturn(false);
    when(() => service.isReminderDegraded).thenReturn(false);
    when(() => service.requestPermission()).thenAnswer((_) async => true);
    when(
      () => service.scheduleDailyReminder(18, 0),
    ).thenAnswer((_) async => false);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsPage(notificationService: service),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final reminderSwitch = find.byType(Switch).first;
    final switchWidget = tester.widget<Switch>(reminderSwitch);
    expect(switchWidget.value, isFalse);

    switchWidget.onChanged!(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.widget<Switch>(reminderSwitch).value, isFalse);
    expect(find.text('每日提醒设置失败，请稍后重试'), findsOneWidget);
    verify(() => service.scheduleDailyReminder(18, 0)).called(1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('提醒开着但本机排不上时，页面明确提示未生效', (tester) async {
    // 回归点：旧实现把这种情况改写成开关关闭，用户看到的是「自己关了」，
    // 既看不出问题也不会去查权限。现在开关保持打开并给出可行动的提示。
    final service = _MockNotificationService();
    when(() => service.isReminderEnabled).thenReturn(true);
    when(() => service.reminderHour).thenReturn(18);
    when(() => service.reminderMinute).thenReturn(0);
    when(() => service.isWeeklyReportEnabled).thenReturn(false);
    when(() => service.isReminderDegraded).thenReturn(true);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsPage(notificationService: service),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.textContaining('提醒未能生效'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('无降级标记时不显示未生效提示', (tester) async {
    final service = _MockNotificationService();
    when(() => service.isReminderEnabled).thenReturn(true);
    when(() => service.reminderHour).thenReturn(18);
    when(() => service.reminderMinute).thenReturn(0);
    when(() => service.isWeeklyReportEnabled).thenReturn(false);
    when(() => service.isReminderDegraded).thenReturn(false);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsPage(notificationService: service),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('提醒未能生效'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
