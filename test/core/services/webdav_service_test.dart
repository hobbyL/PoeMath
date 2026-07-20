import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/webdav_service.dart';
import 'package:poemath/data/models/webdav_config.dart';

WebDavConfig _config({
  String url = 'https://dav.example.com',
  String username = 'alice',
  String password = 'secret',
  String remotePath = '/poemath/',
}) {
  return WebDavConfig(
    id: 'test',
    name: '测试 WebDAV',
    url: url,
    username: username,
    password: password,
    remotePath: remotePath,
  );
}

void main() {
  test('URL 校验只允许 HTTPS 且拒绝凭据和 query', () {
    expect(WebDavConfig.validateUrl('https://dav.example.com'), isNull);
    expect(
      WebDavConfig.validateUrl('http://dav.example.com'),
      contains('HTTPS'),
    );
    expect(
      WebDavConfig.validateUrl('https://alice:secret@dav.example.com'),
      contains('账号或密码'),
    );
    expect(
      WebDavConfig.validateUrl('https://dav.example.com?token=secret'),
      contains('query'),
    );
    expect(
      WebDavConfig.validateUrl('https://dav.example.com?'),
      contains('query'),
    );
    expect(
      WebDavConfig.validateUrl('https://dav.example.com#'),
      contains('query'),
    );
    expect(
      WebDavConfig.validateUrl('https://'),
      isNotNull,
    );
  });

  test('HTTP、URL 凭据和路径越界在发出请求前被拒绝', () async {
    var requestCount = 0;
    final service = WebDavService(
      client: MockClient((request) async {
        requestCount++;
        return http.Response('', 207);
      }),
    );
    addTearDown(service.dispose);

    for (final config in <WebDavConfig>[
      _config(url: 'http://dav.example.com'),
      _config(url: 'https://alice:secret@dav.example.com'),
      _config(remotePath: '/../private/'),
    ]) {
      await expectLater(
        service.testConnection(config),
        throwsA(isA<WebDavException>()),
      );
      await expectLater(
        service.upload(config, '{}'),
        throwsA(isA<WebDavException>()),
      );
      await expectLater(
        service.download(config),
        throwsA(isA<WebDavException>()),
      );
    }

    expect(requestCount, 0);
  });

  test('缺少凭据或远程目录时在发出请求前被拒绝', () async {
    var requestCount = 0;
    final service = WebDavService(
      client: MockClient((request) async {
        requestCount++;
        return http.Response('', 207);
      }),
    );
    addTearDown(service.dispose);

    for (final config in <WebDavConfig>[
      _config(username: ''),
      _config(password: ''),
      _config(remotePath: '  '),
    ]) {
      await expectLater(
        service.testConnection(config),
        throwsA(isA<WebDavException>()),
      );
    }

    expect(requestCount, 0);
  });

  test('认证失败的连接返回 false', () async {
    final service = WebDavService(
      client: MockClient((request) async => http.Response('', 401)),
    );
    addTearDown(service.dispose);

    expect(await service.testConnection(_config()), isFalse);
  });

  test('HTTPS 请求使用 Basic Auth 且路径拼接规范', () async {
    final methods = <String>[];
    final urls = <Uri>[];
    final authorizationHeaders = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      urls.add(request.url);
      authorizationHeaders.add(
        request.headers['authorization'] ??
            request.headers['Authorization'] ??
            '',
      );
      if (request.method == 'PROPFIND') return http.Response('', 207);
      if (request.method == 'PUT') return http.Response('', 201);
      return http.Response('', 500);
    });
    final service = WebDavService(client: client);
    addTearDown(service.dispose);
    final config = _config(remotePath: 'poemath');

    expect(await service.testConnection(config), isTrue);
    await service.upload(config, '{"version":1}');

    final expectedAuth = 'Basic ${base64Encode(utf8.encode('alice:secret'))}';
    expect(methods, <String>['PROPFIND', 'PROPFIND', 'PUT']);
    expect(urls[0], Uri.parse('https://dav.example.com/poemath/'));
    expect(
      urls[2],
      Uri.parse('https://dav.example.com/poemath/poemath_backup.json'),
    );
    expect(
      authorizationHeaders,
      everyElement(expectedAuth),
    );
  });
}
