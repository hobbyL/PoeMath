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
}
