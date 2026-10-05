import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';

AppVersionInfo _buildVersion({
  String packageName = 'com.poemath.app',
  int versionCode = 100,
}) {
  return AppVersionInfo(
    packageName: packageName,
    versionName: '1.0.0',
    versionCode: versionCode,
  );
}

AppUpdateInfo _buildUpdate({
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

void main() {
  group('apkCompatibilityError', () {
    test('APK 元数据不可用时返回阻止安装提示', () {
      final error = apkCompatibilityError(
        latest: _buildUpdate(),
        current: _buildVersion(),
        apk: null,
      );

      expect(error, '无法读取安装包信息，已阻止安装。');
    });

    test('APK 包名与当前应用不一致时返回不一致提示', () {
      final error = apkCompatibilityError(
        latest: _buildUpdate(),
        current: _buildVersion(packageName: 'com.poemath.app'),
        apk: _buildVersion(packageName: 'com.other.app', versionCode: 200),
      );

      expect(error, '安装包名 com.other.app 与当前应用 com.poemath.app 不一致。');
    });

    test('APK 包名与更新信息不一致时返回不一致提示', () {
      // apk 包名与当前应用一致、与 latest 不一致才走到该分支。
      final error = apkCompatibilityError(
        latest: _buildUpdate(packageName: 'com.poemath.new'),
        current: _buildVersion(packageName: 'com.poemath.app'),
        apk: _buildVersion(packageName: 'com.poemath.app', versionCode: 200),
      );

      expect(
        error,
        '安装包名 com.poemath.app 与更新信息 com.poemath.new 不一致。',
      );
    });

    test('APK 版本号与更新信息不一致时返回不一致提示', () {
      final error = apkCompatibilityError(
        latest: _buildUpdate(versionCode: 200),
        current: _buildVersion(versionCode: 100),
        apk: _buildVersion(packageName: 'com.poemath.app', versionCode: 199),
      );

      expect(error, '安装包版本号 199 与更新信息 200 不一致。');
    });

    test('APK 版本不高于当前版本时返回阻止安装提示', () {
      final sameVersion = apkCompatibilityError(
        latest: _buildUpdate(versionCode: 200),
        current: _buildVersion(versionCode: 200),
        apk: _buildVersion(packageName: 'com.poemath.app', versionCode: 200),
      );
      final olderVersion = apkCompatibilityError(
        latest: _buildUpdate(versionCode: 200),
        current: _buildVersion(versionCode: 210),
        apk: _buildVersion(packageName: 'com.poemath.app', versionCode: 200),
      );

      expect(sameVersion, '安装包版本不高于当前版本，已阻止安装。');
      expect(olderVersion, '安装包版本不高于当前版本，已阻止安装。');
    });

    test('三方一致且版本更高时返回 null', () {
      final error = apkCompatibilityError(
        latest: _buildUpdate(versionCode: 200),
        current: _buildVersion(versionCode: 100),
        apk: _buildVersion(packageName: 'com.poemath.app', versionCode: 200),
      );

      expect(error, isNull);
    });
  });

  group('friendlyUpdateError', () {
    test('UpdateConfigurationException 返回未配置文案', () {
      expect(
        friendlyUpdateError(
          const UpdateConfigurationException(),
          fallback: '后备文案',
        ),
        '当前安装包未配置更新检查地址。',
      );
    });

    test('404 返回更新信息不存在文案', () {
      expect(
        friendlyUpdateError(
          const UpdateException('失败', statusCode: 404),
          fallback: '后备文案',
        ),
        '更新信息不存在，请确认发布配置。',
      );
    });

    test('429 返回请求频繁文案', () {
      expect(
        friendlyUpdateError(
          const UpdateException('失败', statusCode: 429),
          fallback: '后备文案',
        ),
        '请求过于频繁，请稍后重试。',
      );
    });

    test('5xx 返回服务不可用文案', () {
      expect(
        friendlyUpdateError(
          const UpdateException('失败', statusCode: 500),
          fallback: '后备文案',
        ),
        '更新服务暂时不可用，请稍后重试。',
      );
      expect(
        friendlyUpdateError(
          const UpdateException('失败', statusCode: 503),
          fallback: '后备文案',
        ),
        '更新服务暂时不可用，请稍后重试。',
      );
    });

    test('UpdateException message 非空时透传消息', () {
      expect(
        friendlyUpdateError(
          const UpdateException('安装包校验失败，已阻止安装。'),
          fallback: '后备文案',
        ),
        '安装包校验失败，已阻止安装。',
      );
    });

    test('UpdateException message 为空时返回 fallback', () {
      expect(
        friendlyUpdateError(
          const UpdateException(''),
          fallback: '后备文案',
        ),
        '后备文案',
      );
    });

    test('UpdateInstallException 透传安装器消息', () {
      expect(
        friendlyUpdateError(
          const UpdateInstallException('安装失败'),
          fallback: '后备文案',
        ),
        '安装失败',
      );
    });

    test('未知异常返回 fallback', () {
      expect(
        friendlyUpdateError(
          const FormatException('坏数据'),
          fallback: '后备文案',
        ),
        '后备文案',
      );
    });
  });
}
