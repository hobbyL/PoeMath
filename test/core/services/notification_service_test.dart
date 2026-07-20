import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/hive_test_helper.dart';

class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
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
}
