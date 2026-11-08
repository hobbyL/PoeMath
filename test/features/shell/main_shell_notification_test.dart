import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_check_controller.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/features/shell/main_shell.dart';

import '../../helpers/hive_test_helper.dart';

class _Notifications extends Mock implements FlutterLocalNotificationsPlugin {}

class _NoUpdate extends UpdateCheckController {
  _NoUpdate()
    : super(
        updateCheckConfigured: false,
        client: UpdateClient(updateUrl: 'https://example.invalid'),
        installer: AndroidUpdateInstaller(isAndroid: false),
        onAvailable: (_, _) {},
      );
  @override
  Future<void> maybeCheck() async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue((NotificationResponse _) {});
  });
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);
  for (final cold in [false, true]) {
    for (final (payload, destination) in [
      (NotificationService.payloadDailyReminder, '诗词复习目的页'),
      (NotificationService.payloadWeeklyReport, '学习周报目的页'),
      ('unknown', '首页目的页'),
    ]) {
      testWidgets('${cold ? '冷启动' : '前台'}通知 $payload 进入 $destination', (
        tester,
      ) async {
        final plugin = _Notifications();
        when(() => plugin.cancel(any())).thenAnswer((_) async {});
        when(
          () => plugin.initialize(
            any(),
            onDidReceiveNotificationResponse: any(
              named: 'onDidReceiveNotificationResponse',
            ),
          ),
        ).thenAnswer((_) async => true);
        when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
          (_) async => NotificationAppLaunchDetails(
            cold,
            notificationResponse: cold
                ? NotificationResponse(
                    notificationResponseType:
                        NotificationResponseType.selectedNotification,
                    payload: payload,
                  )
                : null,
          ),
        );
        final notifications = NotificationService.forTesting(
          plugin: plugin,
          localTimeZoneIdentifierResolver: () async => 'UTC',
        );
        await tester.runAsync(notifications.initialize);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (_, _) => MainShell(
                notifications: notifications,
                updateControllerFactory: (_) => _NoUpdate(),
                child: const Scaffold(body: Text('首页目的页')),
              ),
            ),
            GoRoute(
              path: AppRoutes.poemReview,
              builder: (_, _) => const Scaffold(body: Text('诗词复习目的页')),
            ),
            GoRoute(
              path: AppRoutes.weeklyReport,
              builder: (_, _) => const Scaffold(body: Text('学习周报目的页')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appRouterProvider.overrideWithValue(router)],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        if (!cold) notifications.onNotificationTap!(payload);
        // 初始化发生在真实异步区；冷启动消费需先让其 Future 回调完成。
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.text(destination), findsOneWidget);
        if (cold) {
          expect(
            await tester.runAsync(notifications.consumePendingLaunchPayload),
            isNull,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await drainHiveWritesForTesting(tester);
      });
    }
  }
}
