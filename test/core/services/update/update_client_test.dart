import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/update/update_client.dart';

String _validPayload({String? apkUrl}) {
  return jsonEncode({
    'packageName': 'com.poemath.app',
    'versionName': '1.2.0',
    'versionCode': 2,
    'tagName': 'v1.2.0',
    'channel': 'stable',
    'apkUrl': apkUrl ?? 'https://updates.example.com/poemath.apk',
    'apkSha256': 'a' * 64,
    'apkSize': 1234,
    'mandatory': false,
    'notes': '修复问题',
  });
}

void main() {
  test('fetchLatest 解析并校验更新清单', () async {
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(_validPayload()),
          200,
        ),
      ),
    );

    final update = await client.fetchLatest();
    expect(update.packageName, equals('com.poemath.app'));
    expect(update.versionCode, equals(2));
    expect(update.apkSha256, equals('a' * 64));
  });

  test('清单校验失败时抛出明确错误', () async {
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(_validPayload(apkUrl: 'file:///tmp/update.apk')),
          200,
        ),
      ),
    );

    final update = await client.fetchLatest();
    expect(update.apkUrl, startsWith('file:'));
    await expectLater(
      client.downloadApk(update),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.message,
          'message',
          '安装包下载地址不正确',
        ),
      ),
    );
  });

  test('未配置更新地址和取消令牌可独立验证', () async {
    final client = UpdateClient(updateUrl: '  ');
    expect(client.isConfigured, isFalse);
    await expectLater(
      client.fetchLatest(),
      throwsA(isA<UpdateConfigurationException>()),
    );

    final token = UpdateDownloadCancelToken();
    token.cancel();
    expect(
      () => token.throwIfCancelled(),
      throwsA(isA<UpdateCancelledException>()),
    );
  });
}
