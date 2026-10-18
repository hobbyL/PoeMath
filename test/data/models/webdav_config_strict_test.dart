// test/data/models/webdav_config_strict_test.dart
//
// G5-D1 的闸门：`WebDavConfig` 的合法性判定必须发生在**构造边界**，
// 而不是散落在各个调用点。
//
// 为什么值得单测守：这些判据决定「一条坏配置是让整份配置读取失败，
// 还是被逐条跳过并提示用户」。判据错一格，要么把用户的合法配置静默
// 丢掉（凭据为空被误判非法），要么让 `../..` 之类的路径穿越溜进请求 URL。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/webdav_config.dart';

/// 构造一条合法配置的 JSON 形状，供各用例按需覆盖字段。
Map<String, dynamic> _json({
  Object? id = 'cfg-1',
  Object? name = '我的网盘',
  Object? url = 'https://dav.example.com/dav/',
  Object? username = 'alice',
  Object? password = 'secret',
  Object? remotePath = '/poemath/',
}) =>
    {
      'id': id,
      'name': name,
      'url': url,
      'username': username,
      'password': password,
      'remotePath': remotePath,
    };

void main() {
  group('WebDavConfig.tryCreate', () {
    test('合法输入构造成功且字段保真', () {
      final config = WebDavConfig.tryCreate(
        id: 'cfg-1',
        name: '我的网盘',
        url: 'https://dav.example.com/dav/',
        username: 'alice',
        password: 'secret',
        remotePath: '/poemath/',
      );

      expect(config, isNotNull);
      expect(config!.id, 'cfg-1');
      expect(config.name, '我的网盘');
      expect(config.url, 'https://dav.example.com/dav/');
      expect(config.username, 'alice');
      expect(config.password, 'secret');
      expect(config.remotePath, '/poemath/');
    });

    test('id 为空或纯空白 → null', () {
      for (final bad in ['', ' ', '\t\n']) {
        expect(
          WebDavConfig.tryCreate(
            id: bad,
            name: 'n',
            url: 'https://dav.example.com/',
            username: '',
            password: '',
          ),
          isNull,
          reason: 'id=$bad 应判非法',
        );
      }
    });

    test('明文 http URL → null', () {
      expect(
        WebDavConfig.tryCreate(
          id: 'cfg-1',
          name: 'n',
          url: 'http://dav.example.com/',
          username: '',
          password: '',
        ),
        isNull,
      );
    });

    test('URL 内嵌凭据 / 带 query 或 fragment → null', () {
      const badUrls = [
        'https://alice:secret@dav.example.com/',
        'https://dav.example.com/?token=x',
        'https://dav.example.com/#frag',
        'not-a-url',
        '',
      ];
      for (final bad in badUrls) {
        expect(
          WebDavConfig.tryCreate(
            id: 'cfg-1',
            name: 'n',
            url: bad,
            username: '',
            password: '',
          ),
          isNull,
          reason: 'url=$bad 应判非法',
        );
      }
    });

    test('remotePath 含路径穿越（含百分号编码变体）→ null', () {
      // 判据是「反复解码到稳定后再比对」，所以编码变体必须同样被拒；
      // 只查字面 `..` 的实现会在这里露出。
      const badPaths = [
        '/../etc/',
        '/poemath/../../etc/',
        '/%2e%2e/etc/',
        '/%252e%252e/etc/',
        '/poemath/..%2fetc/',
        '/poemath/./',
        '',
        '/poemath\\backslash/',
        '/poemath/?query/',
        '/poemath/#frag/',
        '/%zz/',
      ];
      for (final bad in badPaths) {
        expect(
          WebDavConfig.tryCreate(
            id: 'cfg-1',
            name: 'n',
            url: 'https://dav.example.com/',
            username: '',
            password: '',
            remotePath: bad,
          ),
          isNull,
          reason: 'remotePath=$bad 应判非法',
        );
      }
    });

    test('凭据为空不算非法（关键判据）', () {
      // Hive 中的配置凭据按设计恒为 ''（saveWebDavConfig 刻意置空），
      // 若把空凭据算作非法，存量配置会在每次读取时被整体丢弃。
      final config = WebDavConfig.tryCreate(
        id: 'cfg-1',
        name: '我的网盘',
        url: 'https://dav.example.com/',
        username: '',
        password: '',
      );

      expect(config, isNotNull);
      expect(config!.username, isEmpty);
      expect(config.password, isEmpty);
    });
  });

  group('WebDavConfig.fromJsonOrNull', () {
    test('合法 JSON → 实例', () {
      final config = WebDavConfig.fromJsonOrNull(_json());
      expect(config, isNotNull);
      expect(config!.id, 'cfg-1');
      expect(config.remotePath, '/poemath/');
    });

    test('缺 id / name / url 或类型不符 → null', () {
      expect(WebDavConfig.fromJsonOrNull(_json(id: null)), isNull);
      expect(WebDavConfig.fromJsonOrNull(_json(name: null)), isNull);
      expect(WebDavConfig.fromJsonOrNull(_json(url: null)), isNull);
      expect(WebDavConfig.fromJsonOrNull(_json(id: 123)), isNull);
      expect(WebDavConfig.fromJsonOrNull(_json(url: true)), isNull);
    });

    test('username / password / remotePath 缺失时退化为默认值', () {
      final json = _json()
        ..remove('username')
        ..remove('password')
        ..remove('remotePath');

      final config = WebDavConfig.fromJsonOrNull(json);
      expect(config, isNotNull);
      expect(config!.username, isEmpty);
      expect(config.password, isEmpty);
      expect(config.remotePath, '/poemath/');
    });

    test('非字符串的 username / password 退化为空串而非抛异常', () {
      final config = WebDavConfig.fromJsonOrNull(
        _json(username: 42, password: <String>[]),
      );
      expect(config, isNotNull);
      expect(config!.username, isEmpty);
      expect(config.password, isEmpty);
    });

    test('非法 url → null（不在 JSON 层放行）', () {
      expect(
        WebDavConfig.fromJsonOrNull(_json(url: 'http://dav.example.com/')),
        isNull,
      );
    });
  });

  group('WebDavConfig.decodeListDetailed', () {
    test('null / 空串 → 空列表且 skipped 为 0', () {
      for (final input in [null, '']) {
        final result = WebDavConfig.decodeListDetailed(input);
        expect(result.configs, isEmpty);
        expect(result.skipped, 0);
      }
    });

    test('坏 JSON → ([], 0)，不算「有 N 条不合法」', () {
      // 整串损坏属于「存储项损坏」，不是逐条非法；提示文案「有 N 条
      // 配置因不合法被忽略」在这种情况下会误导用户。
      for (final broken in ['{', 'not json', '[1,2', '{"a":1}']) {
        final result = WebDavConfig.decodeListDetailed(broken);
        expect(result.configs, isEmpty, reason: 'input=$broken');
        expect(result.skipped, 0, reason: 'input=$broken');
      }
    });

    test('混合列表：1 合法 + 2 非法 → (1, 2)', () {
      final json = jsonEncode([
        _json(id: 'ok'),
        _json(id: 'bad-url', url: 'ftp://dav.example.com/'),
        _json(id: 'bad-path', remotePath: '/../escape/'),
      ]);

      final result = WebDavConfig.decodeListDetailed(json);

      expect(result.configs.map((c) => c.id), ['ok']);
      expect(result.skipped, 2);
    });

    test('凭据为空的合法配置计入 configs，不计 skipped', () {
      // 这条守的是「Hive 里的配置凭据恒为空」这个不变量：
      // 若判据把空凭据当非法，正常用户会看到「有 3 条配置因不合法被忽略」，
      // 且列表恒为空。
      final json = jsonEncode([
        _json(id: 'a', username: '', password: ''),
        _json(id: 'b', username: '', password: ''),
        _json(id: 'c', username: '', password: ''),
      ]);

      final result = WebDavConfig.decodeListDetailed(json);

      expect(result.configs.map((c) => c.id), ['a', 'b', 'c']);
      expect(result.skipped, 0);
    });

    test('列表内的非对象元素计入 skipped', () {
      final json = jsonEncode([
        _json(id: 'ok'),
        'not-an-object',
        42,
        null,
      ]);

      final result = WebDavConfig.decodeListDetailed(json);

      expect(result.configs.map((c) => c.id), ['ok']);
      expect(result.skipped, 3);
    });

    test('全非法 → (0, N)，不抛异常', () {
      final json = jsonEncode([
        _json(url: 'http://a.example.com/'),
        _json(url: 'http://b.example.com/'),
      ]);

      final result = WebDavConfig.decodeListDetailed(json);

      expect(result.configs, isEmpty);
      expect(result.skipped, 2);
    });
  });

  group('WebDavConfig.decodeList（兼容包装）', () {
    test('等价于 decodeListDetailed().configs', () {
      final json = jsonEncode([
        _json(id: 'ok', username: '', password: ''),
        _json(id: 'bad', url: 'http://dav.example.com/'),
      ]);

      final legacy = WebDavConfig.decodeList(json);
      final detailed = WebDavConfig.decodeListDetailed(json);

      expect(legacy.map((c) => c.id), detailed.configs.map((c) => c.id));
      expect(legacy.map((c) => c.id), ['ok']);
    });

    test('坏 JSON → 空列表（沿用旧行为）', () {
      expect(WebDavConfig.decodeList('{{'), isEmpty);
      expect(WebDavConfig.decodeList(null), isEmpty);
    });
  });

  group('WebDavConfig.fromJson（@Deprecated）', () {
    test('合法 JSON 仍可用', () {
      // ignore: deprecated_member_use_from_same_package
      final config = WebDavConfig.fromJson(_json());
      expect(config.id, 'cfg-1');
    });

    test('非法 JSON 抛 FormatException 而非裸 TypeError', () {
      // 旧实现的 `json['id'] as String` 在缺字段时抛 TypeError，
      // 语义模糊且可能被 `on Exception` 漏掉（TypeError 不是 Exception）。
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => WebDavConfig.fromJson(_json(url: 'http://dav.example.com/')),
        throwsA(isA<FormatException>()),
      );
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => WebDavConfig.fromJson(const {}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
