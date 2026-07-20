import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/update/android_update_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('poemath.test/app_update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('注入 Android 平台后转发版本、APK 和权限方法', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getAppVersion' => <String, Object?>{
            'packageName': 'com.poemath.app',
            'versionName': '1.2.3',
            'versionCode': 123,
          },
        'inspectApk' => <String, Object?>{
            'packageName': 'com.poemath.app',
            'versionName': '1.3.0',
            'versionCode': 130,
          },
        'canRequestPackageInstalls' => true,
        _ => null,
      };
    });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: true,
    );

    expect(installer.isSupported, isTrue);
    expect(
      (await installer.getCurrentVersion()).versionCode,
      equals(123),
    );
    expect(
      (await installer.inspectApk('/tmp/update.apk'))!.versionName,
      equals('1.3.0'),
    );
    expect(await installer.canRequestPackageInstalls(), isTrue);
    await installer.openInstallPermissionSettings();
    await installer.installApk('/tmp/update.apk');

    expect(
      calls.map((call) => call.method),
      <String>[
        'getAppVersion',
        'inspectApk',
        'canRequestPackageInstalls',
        'openInstallPermissionSettings',
        'installApk',
      ],
    );
    expect(calls[1].arguments, <String, String>{'path': '/tmp/update.apk'});
  });

  test('MethodChannel PlatformException 被转换为 UpdateInstallException', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'FILE_NOT_FOUND',
        message: '安装包文件不存在',
      ),
    );
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: true,
    );

    await expectLater(
      installer.installApk('/missing.apk'),
      throwsA(
        isA<UpdateInstallException>().having(
          (error) => error.message,
          'message',
          '安装包文件不存在',
        ),
      ),
    );
  });

  test('必需的 MethodChannel 返回空值时失败', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: true,
    );

    await expectLater(
      installer.getCurrentVersion(),
      throwsA(
        isA<UpdateInstallException>().having(
          (error) => error.message,
          'message',
          'Android 返回了空结果',
        ),
      ),
    );
  });

  test('非 Android 平台在调用通道前失败', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      invoked = true;
      return null;
    });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: false,
    );

    expect(installer.isSupported, isFalse);
    await expectLater(
      installer.installApk('/update.apk'),
      throwsA(isA<UpdateInstallException>()),
    );
    expect(invoked, isFalse);
  });
}
