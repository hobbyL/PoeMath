import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_check_controller.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';

/// 可注入返回值/异常并统计调用次数的 fake 客户端。
class _FakeUpdateClient extends UpdateClient {
  _FakeUpdateClient({AppUpdateInfo? latest, Object? error})
      : _latest = latest,
        _error = error,
        super(updateUrl: 'https://example.com/latest.json');

  final AppUpdateInfo? _latest;
  final Object? _error;
  int fetchCount = 0;

  @override
  Future<AppUpdateInfo> fetchLatest() async {
    fetchCount++;
    final error = _error;
    if (error != null) throw error;
    return _latest!;
  }
}

/// 覆写平台支持与当前版本的 fake 安装器。
class _FakeUpdateInstaller extends AndroidUpdateInstaller {
  _FakeUpdateInstaller({
    required AppVersionInfo current,
    bool supported = true,
  })  : _current = current,
        _supported = supported,
        super(isAndroid: true);

  final AppVersionInfo _current;
  final bool _supported;

  @override
  bool get isSupported => _supported;

  @override
  Future<AppVersionInfo> getCurrentVersion() async => _current;
}

AppVersionInfo _currentVersion({
  String packageName = 'com.poemath.app',
  int versionCode = 100,
}) {
  return AppVersionInfo(
    packageName: packageName,
    versionName: '1.0.0',
    versionCode: versionCode,
  );
}

AppUpdateInfo _newUpdate({
  String packageName = 'com.poemath.app',
  int versionCode = 200,
}) {
  return AppUpdateInfo(
    packageName: packageName,
    versionName: '2.0.0',
    versionCode: versionCode,
    tagName: 'v2.0.0',
    channel: 'stable',
    apkUrl: 'https://example.com/poemath.apk',
    apkSha256: 'a' * 64,
    apkSize: 12345,
    mandatory: false,
    notes: '更新说明',
  );
}

UpdateCheckController _buildController(
  _FakeUpdateClient client, {
  required List<AppUpdateInfo> available,
  List<AppVersionInfo>? currentVersions,
  _FakeUpdateInstaller? installer,
  bool updateCheckConfigured = true,
  Duration recheckInterval = const Duration(hours: 1),
  DateTime Function()? now,
}) {
  return UpdateCheckController(
    updateCheckConfigured: updateCheckConfigured,
    client: client,
    installer:
        installer ?? _FakeUpdateInstaller(current: _currentVersion()),
    onAvailable: (update, current) {
      available.add(update);
      currentVersions?.add(current);
    },
    recheckInterval: recheckInterval,
    now: now,
  );
}

void main() {
  test('enabled=false（未配置 URL 或非 Android 平台）时零网络请求', () async {
    final noUrlClient = _FakeUpdateClient(latest: _newUpdate());
    final notAndroidClient = _FakeUpdateClient(latest: _newUpdate());

    final noUrl = _buildController(
      noUrlClient,
      available: [],
      updateCheckConfigured: false,
    );
    final notAndroid = _buildController(
      notAndroidClient,
      available: [],
      installer: _FakeUpdateInstaller(
        current: _currentVersion(),
        supported: false,
      ),
    );

    expect(noUrl.enabled, isFalse);
    expect(notAndroid.enabled, isFalse);

    await noUrl.maybeCheck();
    await notAndroid.maybeCheck();

    expect(noUrlClient.fetchCount, 0);
    expect(notAndroidClient.fetchCount, 0);
  });

  test('首次 maybeCheck 恰请求一次并在有新版时回调 onAvailable', () async {
    final client = _FakeUpdateClient(latest: _newUpdate());
    final available = <AppUpdateInfo>[];
    final currents = <AppVersionInfo>[];
    final controller = _buildController(
      client,
      available: available,
      currentVersions: currents,
    );

    expect(controller.enabled, isTrue);
    await controller.maybeCheck();

    expect(client.fetchCount, 1);
    expect(available, hasLength(1));
    expect(available.single.versionCode, 200);
    // 回调同时携带当前安装版本（弹窗兼容性校验需要）。
    expect(currents, hasLength(1));
    expect(currents.single.versionCode, 100);
  });

  test('远端版本不新于当前版本时不回调 onAvailable', () async {
    final client = _FakeUpdateClient(latest: _newUpdate(versionCode: 100));
    final available = <AppUpdateInfo>[];
    final controller = _buildController(client, available: available);

    await controller.maybeCheck();

    expect(client.fetchCount, 1);
    expect(available, isEmpty);
  });

  test('更新包名与当前应用不一致时不回调 onAvailable', () async {
    final client = _FakeUpdateClient(
      latest: _newUpdate(packageName: 'com.other.app'),
    );
    final available = <AppUpdateInfo>[];
    final controller = _buildController(client, available: available);

    await controller.maybeCheck();

    expect(client.fetchCount, 1);
    expect(available, isEmpty);
  });

  test('fetchLatest 抛异常时静默吞掉且不回调 onAvailable', () async {
    final client = _FakeUpdateClient(error: const UpdateException('网络失败'));
    final available = <AppUpdateInfo>[];
    var currentTime = DateTime(2026, 1, 1, 10);
    final controller = _buildController(
      client,
      available: available,
      now: () => currentTime,
    );

    await controller.maybeCheck();

    expect(client.fetchCount, 1);
    expect(available, isEmpty);

    // finally 复位 _checking：时间越过间隔后可再次进入检测。
    currentTime = currentTime.add(const Duration(hours: 1));
    await controller.maybeCheck();
    expect(client.fetchCount, 2);
    expect(available, isEmpty);
  });

  test('检测进行中重入不重复请求', () async {
    final client = _FakeUpdateClient(latest: _newUpdate());
    final available = <AppUpdateInfo>[];
    final controller = _buildController(client, available: available);

    // async 函数同步执行到首个 await，调用返回时 _checking 已为 true。
    final first = controller.maybeCheck();
    await controller.maybeCheck();
    await first;

    expect(client.fetchCount, 1);
    expect(available, hasLength(1));
  });

  test('弹窗显示中（markDialogShown）不再检测', () async {
    final client = _FakeUpdateClient(latest: _newUpdate());
    final available = <AppUpdateInfo>[];
    final controller = _buildController(client, available: available);

    controller.markDialogShown();
    expect(controller.hasActiveDialog, isTrue);

    await controller.maybeCheck();
    expect(client.fetchCount, 0);

    // 关闭弹窗后恢复检测。
    controller.markDialogClosed();
    expect(controller.hasActiveDialog, isFalse);
    await controller.maybeCheck();
    expect(client.fetchCount, 1);
  });

  test('用户取消后本进程内不再检测', () async {
    final client = _FakeUpdateClient(latest: _newUpdate());
    final available = <AppUpdateInfo>[];
    final controller = _buildController(client, available: available);

    controller.markDismissedByUser();
    expect(controller.dismissedByUser, isTrue);

    await controller.maybeCheck();
    expect(client.fetchCount, 0);
  });

  test('距上次检测不足间隔不重复请求，达到间隔后重新请求', () async {
    final client = _FakeUpdateClient(latest: _newUpdate(versionCode: 100));
    final available = <AppUpdateInfo>[];
    var currentTime = DateTime(2026, 1, 1, 10);
    final controller = _buildController(
      client,
      available: available,
      now: () => currentTime,
    );

    await controller.maybeCheck();
    expect(client.fetchCount, 1);

    currentTime = currentTime.add(const Duration(minutes: 30));
    await controller.maybeCheck();
    expect(client.fetchCount, 1);

    currentTime = currentTime.add(const Duration(hours: 1));
    await controller.maybeCheck();
    expect(client.fetchCount, 2);
    expect(available, isEmpty);
  });

  test('检测失败后立即 resumed 不再请求（_lastCheckAt 先记）', () async {
    final client = _FakeUpdateClient(error: const UpdateException('超时'));
    final available = <AppUpdateInfo>[];
    final controller = _buildController(client, available: available);

    await controller.maybeCheck();
    expect(client.fetchCount, 1);

    await controller.maybeCheck();
    expect(client.fetchCount, 1);
  });
}
