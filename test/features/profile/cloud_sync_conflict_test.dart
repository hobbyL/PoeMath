// test/features/profile/cloud_sync_conflict_test.dart
//
// 跨设备同步冲突检测的端到端闸门：
//   - 下载方向：云端 exportedAt 晚于本机 last_synced_at → 弹框；取消 = 零变更。
//   - 上传方向：双向都有新进展 → 先拉云端比对，弹框；取消 = 不上传。
//   - 无 last_synced_at（首次配置）→ 不弹框，不阻断。
//
// 时间线读的是本机 Hive 的 last_synced_at 与云端备份顶层的 exportedAt，
// 两者都必须在测试里可控，否则只能断言「有时弹有时不弹」。
//
// ⚠️ Hive 的初始化与读写必须包在 `tester.runAsync()` 里。
// `testWidgets` 把测试体跑在 FakeAsync 中，而 `setUpHiveForTesting()` 依赖
// `Directory.systemTemp.createTemp` / `Hive.init` / box open 这些**真实文件
// IO** —— FakeAsync 只 flush microtask、不跑真实事件循环，于是这些 Future
// 永不完成，测试表现为挂到 flutter 的 10 分钟上限（无任何报错栈）。
// 最小复现：`testWidgets((t) async { await setUpHiveForTesting(); })` 即挂死。
// 纯 microtask 的假客户端（`MockClient`）不受影响，所以只有 Hive 侧要包。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:http/testing.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/webdav_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/cloud_sync_page.dart';

import '../../helpers/hive_test_helper.dart';

/// 只报告「凭据不存在」的假安全存储：不触发任何平台通道。
final class _NoCredentialStore extends SecureCredentialStore {
  _NoCredentialStore() : super(storage: const _InertSecureStorage());

  @override
  Future<String?> readBackupPassphrase() async => null;

  @override
  Future<({String username, String password})?> readWebDavCredentials(
    String configId,
  ) async =>
      (username: 'alice', password: 'secret');
}

/// 真正不碰平台通道的假存储，用作 `NoCredentialStore` 的底座。
///
/// `SecureCredentialStore` 覆写的方法若忘了加 `async`，调用就会穿透到底层
/// `FlutterSecureStorage` 的平台通道 —— 在 widget test 里那个通道永不回应，
/// 表现为测试挂到 10 分钟超时。显式传入假底层实现，把这类疏漏变成编译期
/// 不可能（此处 init 也不做任何 IO）。
final class _InertSecureStorage implements FlutterSecureStorage {
  const _InertSecureStorage();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试不应访问安全存储: ${invocation.memberName}');
}

/// 恢复成功后 `reconcileWithStoredSettings()` 会走真实 `NotificationService`：
/// 其 `initialize()` 要过 `FlutterLocalNotificationsPlugin` 与
/// `FlutterTimezone.getLocalTimezone()` 两个平台通道，widget test 里无人应答，
/// 表现为测试挂到超时。这里注入假插件 + 假时区解析器（`timezone` 包内置
/// `Asia/Shanghai`），让通知侧的异步链在纯 Dart 里走完。
NotificationService _testNotificationService() {
  return NotificationService.forTesting(
    plugin: const _InertNotificationsPlugin(),
    localTimeZoneIdentifierResolver: () async => 'Asia/Shanghai',
  );
}

/// 记录调用、绝不触达平台通道的通知插件。
///
/// 这里逐个实现 `NotificationService` 真正会调用的方法，而不是靠
/// `noSuchMethod` 兜底：接口里 `initialize()` / `cancel()` 等声明了**参数化
/// 返回类型**（`Future<bool?>`、`Future<void>`），而 `noSuchMethod` 无论返回
/// `null` 还是 `Future<dynamic>`，都会在调用点触发
/// `type '...' is not a subtype of type 'Future<bool?>'`。
/// `resolvePlatformSpecificImplementation` 返回 null，让平台专有分支自然跳过。
final class _InertNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  const _InertNotificationsPlugin();

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async =>
      null;

  @override
  T? resolvePlatformSpecificImplementation<
      T extends FlutterLocalNotificationsPlatform>() => null;

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    NotificationDetails notificationDetails, {
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {}

  @override
  Future<void> cancel(int id, {String? tag}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 可控的云端备份内容；每次 GET 都返回当前值。
final class _FakeCloud {
  _FakeCloud({required this.content});

  String content;
  int puts = 0;
  bool failGet = false;

  http.Client get client => MockClient((request) async {
        if (request.method == 'GET') {
          if (failGet) return http.Response('boom', 500);
          return http.Response.bytes(utf8.encode(content), 200);
        }
        if (request.method == 'PUT') {
          puts++;
          content = request.body;
          return http.Response('', 201);
        }
        // PROPFIND / MKCOL：目录已存在。
        return http.Response('', 207);
      });
}

String _backupJson({required DateTime exportedAt, int checkIns = 0}) {
  return jsonEncode(<String, dynamic>{
    'version': 1,
    'exportedAt': exportedAt.toIso8601String(),
    'checkIns': <Map<String, dynamic>>[
      for (var i = 0; i < checkIns; i++)
        <String, dynamic>{
          'profileId': 'default',
          'date': '2026-10-0${i + 1}',
        },
    ],
    'settings': <String, dynamic>{'theme_mode': 'light'},
  });
}

void main() {
  late _FakeCloud cloud;
  final remoteConfig = WebDavConfig(
    id: 'dav-1',
    name: '家庭云盘',
    url: 'https://dav.example.com',
    username: '',
    password: '',
    remotePath: '/poemath',
  );

  /// 点一个按钮并等待它触发的真实异步链跑完。
  ///
  /// `tap` 的 onPressed 里会做真实 IO（Hive 读写、WebDAV 请求）。FakeAsync
  /// 不跑真实事件循环，`pumpAndSettle` 只会看到进度圈在转、帧数超限而报
  /// 「pumpAndSettle timed out」。把 tap 与一段真实等待放进 `runAsync`，
  /// 再用裸 `pump()` 收尾，是项目里已验证的写法
  /// （见 `word_problem_preview_page_test.dart`）。
  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 装好 Hive、渲染页面、选中唯一配置（底部操作按钮随之出现）。
  ///
  /// [before] 在 Hive 就绪后、渲染前执行，用于预置 last_synced_at 等本机状态；
  /// 它同样被包在 `runAsync` 里（Hive 写入是真实 IO）。
  Future<void> pumpPage(
    WidgetTester tester,
    _FakeCloud fake, {
    Future<void> Function()? before,
  }) async {
    await tester.runAsync(() async {
      await setUpHiveForTesting();
      await HiveBoxes.settings.put(
        'webdav_configs',
        jsonEncode([remoteConfig.toJson()]),
      );
      await before?.call();
    });
    addTearDown(() => tester.runAsync(tearDownHiveForTesting));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webDavServiceProvider.overrideWithValue(
            WebDavService(client: fake.client),
          ),
          secureCredentialStoreProvider
              .overrideWithValue(_NoCredentialStore()),
        ],
        child: MaterialApp(
          home: CloudSyncPage(
            notificationService: _testNotificationService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 选中唯一配置，底部操作按钮出现。点击会触发 Hive 读取（真实 IO），
    // 故同样包进 runAsync。
    await tapAndSettle(tester, find.text('家庭云盘'));
  }

  testWidgets('下载：云端比本机新 → 弹冲突框；取消后本机数据零变更', (tester) async {
    cloud = _FakeCloud(
      content: _backupJson(
        exportedAt: DateTime(2026, 10, 13, 15, 45),
        checkIns: 2,
      ),
    );

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
      await HiveBoxes.settings.put('theme_mode', 'dark');
    },);
    await tapAndSettle(tester, find.text('从云端下载'));
    // 覆盖确认（既有的下载二次确认）→ 通过。
    await tapAndSettle(tester, find.text('确认下载'));

    // 冲突框出现。
    expect(find.text('⚠️ 云端数据比本机新'), findsOneWidget);
    await tapAndSettle(tester, find.text('取消'));

    // 零变更：本机数据与时间线都没动。
    expect(HiveBoxes.checkIns.isEmpty, isTrue);
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    expect(
      HiveBoxes.settings.get('last_synced_at'),
      '2026-10-12T08:00:00.000',
    );
  });

  testWidgets('下载：用户确认后恢复，last_synced_at 推进到云端 exportedAt', (tester) async {
    final exportedAt = DateTime(2026, 10, 13, 15, 45);
    cloud = _FakeCloud(content: _backupJson(exportedAt: exportedAt, checkIns: 2));

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('从云端下载'));
    await tapAndSettle(tester, find.text('确认下载'));

    expect(find.text('⚠️ 云端数据比本机新'), findsOneWidget);
    await tapAndSettle(tester, find.text('仍然下载覆盖'));

    expect(HiveBoxes.checkIns.length, 2);
    expect(
      HiveBoxes.settings.get('last_synced_at'),
      exportedAt.toIso8601String(),
    );
  });

  testWidgets('下载：云端不比本机新 → 不弹冲突框', (tester) async {
    cloud = _FakeCloud(
      content: _backupJson(exportedAt: DateTime(2026, 10, 13), checkIns: 1),
    );

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-14T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('从云端下载'));
    await tapAndSettle(tester, find.text('确认下载'));

    expect(find.text('⚠️ 云端数据比本机新'), findsNothing);
    expect(HiveBoxes.checkIns.length, 1);
  });

  testWidgets('下载：无 last_synced_at（首次）→ 不弹冲突框', (tester) async {
    cloud = _FakeCloud(
      content: _backupJson(exportedAt: DateTime(2026, 10, 13), checkIns: 1),
    );

    await pumpPage(tester, cloud);
    await tapAndSettle(tester, find.text('从云端下载'));
    await tapAndSettle(tester, find.text('确认下载'));

    expect(find.text('⚠️ 云端数据比本机新'), findsNothing);
    expect(HiveBoxes.checkIns.length, 1);
  });

  testWidgets('上传：云端在上次同步后被改过 → 弹框（不要求本机也有改动）', (tester) async {
    // 回归锁定：判定曾错误地叠加「本机导出晚于上次同步」这一条件。
    // 备份的 exportedAt 是**导出时刻**（`DateTime.now()`），不是数据变更
    // 时刻，所以该条件对本机本次导出恒为真 —— 它不过滤任何情况，只是把
    // 提示伪装成「双方都有新进展」。
    //
    // 本用例刻意让本机**零改动**（settings 只有 last_synced_at，无业务数据），
    // 云端被别的设备写过。旧判定会因为恒真条件而弹框；新判定同样弹框，
    // 但语义诚实：覆盖云端前用户应当知情。若将来真的引入数据变更时间戳，
    // 此用例即是要被重新审视的行为契约。
    cloud = _FakeCloud(content: _backupJson(exportedAt: DateTime(2026, 10, 14)));

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('上传到云端'));

    expect(find.text('⚠️ 云端数据比本机新'), findsOneWidget);
  });

  testWidgets('上传：云端不比上次同步新 → 不打扰，直接上传', (tester) async {
    // 边界：云端 exportedAt 恰好等于 last_synced_at（同一时刻）时不弹框。
    // `isAfter` 是严格大于，相等不算「被改过」。
    cloud = _FakeCloud(content: _backupJson(exportedAt: DateTime(2026, 10, 12, 8)));

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('上传到云端'));

    expect(find.text('⚠️ 云端数据比本机新'), findsNothing);
    expect(cloud.puts, 1);
  });

  testWidgets('上传：云端 exportedAt 无法解析 → 跳过冲突检测，仍可上传', (tester) async {
    // 老版本备份没有 exportedAt（或被别的内容顶掉）：不得据此判定冲突，
    // 否则换机后第一次上传会被无谓拦截。
    cloud = _FakeCloud(
      content: jsonEncode(<String, dynamic>{
        'version': 1,
        'settings': <String, dynamic>{},
      }),
    );

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('上传到云端'));

    expect(find.text('⚠️ 云端数据比本机新'), findsNothing);
    expect(cloud.puts, 1);
  });

  testWidgets('上传：取消冲突框 → 不发出 PUT，时间线保持原值', (tester) async {
    // 云端更晚（另一台设备写的）。
    cloud = _FakeCloud(content: _backupJson(exportedAt: DateTime(2026, 10, 14)));

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('上传到云端'));

    expect(find.text('⚠️ 云端数据比本机新'), findsOneWidget);
    await tapAndSettle(tester, find.text('取消'));

    // 未发出 PUT；时间线保持原值。
    expect(cloud.puts, 0);
    expect(
      HiveBoxes.settings.get('last_synced_at'),
      '2026-10-12T08:00:00.000',
    );
  });

  testWidgets('上传：确认后 PUT 一次，last_synced_at 推进到本次导出时刻', (tester) async {
    cloud = _FakeCloud(content: _backupJson(exportedAt: DateTime(2026, 10, 14)));

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('上传到云端'));
    await tapAndSettle(tester, find.text('仍然上传覆盖'));

    expect(cloud.puts, 1);

    // 精确断言：上传成功后 `last_synced_at` 必须**逐字节等于**本次 PUT 的
    // `exportedAt`（见 `cloud_sync_page.dart` 上传分支 `setLastSyncedAt(
    // _exportedAtOf(json))`），也就等于云端当前持有的那份备份的 exportedAt。
    //
    // 不要退化成 `DateTime.parse(saved).isAfter(基准)`：那样的断言对任何
    // 「写错了但恰好更晚」的值都成立（比如误写成 DateTime.now()，或把
    // 下载方向的 exportedAt 写进来），等于没验。同文件其他用例都用精确相等。
    final saved = HiveBoxes.settings.get('last_synced_at') as String;
    expect(
      DateTime.parse(saved),
      BackupService.exportedAt(cloud.content),
      reason: '同步时刻应精确推进到本次上传内容的 exportedAt',
    );
    // 同时确认时间线确实**前进了**（而非原地不动恰好相等）。
    expect(
      DateTime.parse(saved).isAfter(DateTime(2026, 10, 12, 8)),
      isTrue,
      reason: '时间线应相对上次同步前进',
    );
  });

  testWidgets('上传：云端读取失败 → 跳过冲突检测，仍可正常上传', (tester) async {
    cloud = _FakeCloud(content: '')..failGet = true;

    await pumpPage(tester, cloud, before: () async {
      await HiveBoxes.settings.put('last_synced_at', '2026-10-12T08:00:00.000');
    },);
    await tapAndSettle(tester, find.text('上传到云端'));

    // 冲突检测是辅助闸门，不能反向阻断正常上传。
    expect(find.text('⚠️ 云端数据比本机新'), findsNothing);
    expect(cloud.puts, 1);
  });
}
