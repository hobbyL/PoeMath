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
        'getApkSignatureSha256' => <String>['aa' * 32],
        'inspectApkSignature' => <String>['aa' * 32],
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
    expect(
      await installer.getInstalledSignatureSha256(),
      equals(<String>['aa' * 32]),
    );
    expect(
      await installer.inspectApkSignature('/tmp/update.apk'),
      equals(<String>['aa' * 32]),
    );
    await installer.installApk('/tmp/update.apk');

    expect(
      calls.map((call) => call.method),
      <String>[
        'getAppVersion',
        'inspectApk',
        'canRequestPackageInstalls',
        'openInstallPermissionSettings',
        'getApkSignatureSha256',
        'inspectApkSignature',
        'installApk',
      ],
    );
    expect(calls[1].arguments, <String, String>{'path': '/tmp/update.apk'});
    expect(calls[5].arguments, <String, String>{'path': '/tmp/update.apk'});
    expect(calls[6].arguments, <String, String>{'path': '/tmp/update.apk'});
  });

  test('inspectApkSignature 返回 null 时透传为 null（区别于空列表）', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'inspectApkSignature') return null;
      return null;
    });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: true,
    );

    expect(await installer.inspectApkSignature('/tmp/update.apk'), isNull);
  });

  test('getInstalledSignatureSha256 返回空结果时失败', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: true,
    );

    await expectLater(
      installer.getInstalledSignatureSha256(),
      throwsA(
        isA<UpdateInstallException>().having(
          (error) => error.message,
          'message',
          'Android 返回了空结果',
        ),
      ),
    );
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

  // 新增原生错误码必须都能映射为用户可见的中文异常。
  test('新增原生错误码映射为 UpdateInstallException', () async {
    const cases = <String, String>{
      'APK_PATH_NOT_ALLOWED': '安装包路径不在允许的下载目录内',
      'FILE_NOT_FOUND': '安装包文件不存在: /sdcard/Download/evil.apk',
      'APK_UNREADABLE': '无法读取安装包信息',
      'APK_PACKAGE_MISMATCH': '安装包包名与应用不一致：com.evil.app',
      'APK_SIGNATURE_UNAVAILABLE': '无法读取签名信息，已阻止安装',
      'APK_SIGNATURE_MISMATCH': '安装包签名与当前应用不一致，已阻止安装',
    };

    for (final entry in cases.entries) {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: entry.key,
          message: entry.value,
        ),
      );
      final installer = AndroidUpdateInstaller(
        channel: channel,
        isAndroid: true,
      );

      await expectLater(
        installer.installApk('/tmp/update.apk'),
        throwsA(
          isA<UpdateInstallException>().having(
            (error) => error.message,
            'message',
            entry.value,
          ),
        ),
        reason: entry.key,
      );
    }
  });

  test('PlatformException 无 message 时用错误码兜底', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'APK_SIGNATURE_MISMATCH'),
    );
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: true,
    );

    await expectLater(
      installer.installApk('/tmp/update.apk'),
      throwsA(
        isA<UpdateInstallException>().having(
          (error) => error.message,
          'message',
          'APK_SIGNATURE_MISMATCH',
        ),
      ),
    );
  });

  test('非 Android 平台调用签名方法不触达通道', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      invoked = true;
      return null;
    });
    final installer = AndroidUpdateInstaller(
      channel: channel,
      isAndroid: false,
    );

    await expectLater(
      installer.getInstalledSignatureSha256(),
      throwsA(isA<UpdateInstallException>()),
    );
    await expectLater(
      installer.inspectApkSignature('/update.apk'),
      throwsA(isA<UpdateInstallException>()),
    );
    expect(invoked, isFalse);
  });
}
