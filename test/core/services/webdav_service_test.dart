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
  test('历史版本写失败时不会发布latest，历史列表拒绝外部目录与来源', () async {
    final puts = <Uri>[];
    final failed = WebDavService(client: MockClient((request) async {
      if (request.method == 'PROPFIND') return http.Response('', 207);
      puts.add(request.url);
      return http.Response('', 500);
    }),);
    addTearDown(failed.dispose);
    await expectLater(
        failed.upload(_config(), '{}'), throwsA(isA<WebDavException>()),);
    expect(puts, hasLength(1));
    expect(puts.single.path, isNot(endsWith('/poemath_backup.json')));
    const name = 'poemath_backup_1792108800000000_aabbccdd.json';
    final service =
        WebDavService(client: MockClient((request) async => http.Response('''
      <d:multistatus xmlns:d="DAV:">
      <d:response><d:href>/poemath/$name</d:href></d:response>
      <d:response><d:href>https://evil.example/poemath/$name</d:href></d:response>
      <d:response><d:href>/other/$name</d:href></d:response>
      <d:response><d:href>/poemath/nested/$name</d:href></d:response>
      <d:response><d:href>/poemath/poemath_backup.json</d:href></d:response>
      </d:multistatus>''', 207,),),);
    addTearDown(service.dispose);
    expect((await service.listVersions(_config())).map((e) => e.id), [name]);
    expect(() => service.downloadVersion(_config(), '../escape.json'),
        throwsA(isA<WebDavException>()),);
  });

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

  test('远程目录穿越：编码变体与非法字符全部拒绝', () {
    const rejected = <String>[
      '/../private/', // 字面 ..
      '/%2e%2e/private/', // 单层编码
      '/%2E%2E/private/', // 大写十六进制
      '/%252e%252e/private/', // 双层编码（服务端解一次后仍是 ..）
      '/..%2fprivate/', // 编码斜杠
      '/poem%2f..%2fsecret/', // 编码斜杠 + ..
      '/a/./b/', // 单点段
      r'/..\private\', // 反斜杠（部分服务端等价 /）
      '/poemath/../', // 尾随 ..
      '/%zz/', // 无法解码的转义
      '/poemath/?x=1', // query 截断
      '/poemath/#frag', // fragment 截断
    ];

    for (final path in rejected) {
      expect(
        WebDavConfig.validateRemotePath(path),
        isNotNull,
        reason: '「$path」应被拒绝',
      );
    }

    const accepted = <String>['/poemath/', 'poemath', '/a/b/', '/a-b_c.d/'];
    for (final path in accepted) {
      expect(
        WebDavConfig.validateRemotePath(path),
        isNull,
        reason: '「$path」应被接受',
      );
    }

    // 空值走同一条校验，不再是服务层的独立分支。
    expect(WebDavConfig.validateRemotePath('   '), isNotNull);
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
      _config(remotePath: '/%252e%252e/private/'),
      _config(remotePath: '/poem%2f..%2fsecret/'),
      _config(remotePath: r'/..\private\'),
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
    expect(methods, <String>['PROPFIND', 'PROPFIND', 'PUT', 'PUT', 'PROPFIND']);
    expect(urls[2].path,
        matches(RegExp(r'/poemath/poemath_backup_\d+_[a-f0-9]{8}\.json$')),);
    expect(urls[0], Uri.parse('https://dav.example.com/poemath/'));
    expect(
      urls[3],
      Uri.parse('https://dav.example.com/poemath/poemath_backup.json'),
    );
    expect(
      authorizationHeaders,
      everyElement(expectedAuth),
    );
  });
}
