// test/data/repositories/webdav_credential_migration_test.dart
//
// G5-D2 的闸门：历史版本把 WebDAV 明文凭据写进了 Hive（未加密），
// 启动迁移必须把它们搬进安全存储。
//
// 这里守的不是「迁移能跑通」，而是**失败方向**：写安全存储失败时，
// Hive 里的明文必须原样保留 —— 凭据丢掉是不可逆的（用户只能重新手输），
// 而明文多留一轮只是延后修复。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

/// 不触达平台通道的底层存储。
///
/// `SecureCredentialStore` 的方法若忘了 `async`，调用会穿透到
/// `FlutterSecureStorage` 的平台通道 —— 测试环境无人应答，表现为挂到超时。
/// 显式传入假底层让这类疏漏变成编译期不可能。
final class _InertSecureStorage implements FlutterSecureStorage {
  const _InertSecureStorage();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试不应直连底层存储: ${invocation.memberName}');
}

/// 内存凭据存储：记录写入，可注入失败。
final class FakeCredentialStore extends SecureCredentialStore {
  FakeCredentialStore({this.failWrites = false})
      : super(storage: const _InertSecureStorage());

  /// 为 true 时 `saveWebDavCredentials` 抛错，模拟安全存储不可用。
  final bool failWrites;

  /// configId → (username, password)，只保留最后一次写入。
  final Map<String, ({String username, String password})> saved = {};

  @override
  Future<void> saveWebDavCredentials({
    required String configId,
    required String username,
    required String password,
  }) async {
    if (failWrites) throw StateError('模拟安全存储写入失败');
    saved[configId] = (username: username, password: password);
  }

  @override
  Future<void> deleteWebDavCredentials(String configId) async {
    saved.remove(configId);
  }

  /// 读回写入的值 —— 不覆写会穿透到平台通道，测试会挂到超时。
  @override
  Future<({String username, String password})?> readWebDavCredentials(
    String configId,
  ) async =>
      saved[configId];
}

/// 直接写入 Hive 的原始 JSON（绕过 `saveWebDavConfig` 的凭据剥离，
/// 模拟历史版本留下的明文数据）。
Future<void> _seedRawConfigs(List<Map<String, dynamic>> raw) async {
  await HiveBoxes.settings.put(
    'webdav_configs',
    WebDavConfig.encodeList(raw.map(_toConfig).toList()),
  );
}

WebDavConfig _toConfig(Map<String, dynamic> json) => WebDavConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      remotePath: json['remotePath'] as String? ?? '/poemath/',
    );

Map<String, dynamic> _plaintextConfig({
  String id = 'cfg-1',
  String username = 'alice',
  String password = 'secret',
}) =>
    {
      'id': id,
      'name': '我的网盘',
      'url': 'https://dav.example.com/dav/',
      'username': username,
      'password': password,
      'remotePath': '/poemath/',
    };

/// 读出 Hive 中当前持久化的原始 JSON 串。
String? _rawHiveJson() => HiveBoxes.settings.get('webdav_configs') as String?;

void main() {
  late FakeCredentialStore store;
  late SettingsRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  void useStore({bool failWrites = false}) {
    store = FakeCredentialStore(failWrites: failWrites);
    repo = SettingsRepository(credentialStore: store);
  }

  group('migratePlaintextWebDavCredentials', () {
    test('Hive 明文凭据 → 迁入安全存储且 Hive 置空', () async {
      useStore();
      await _seedRawConfigs([_plaintextConfig()]);

      await repo.migratePlaintextWebDavCredentials();

      expect(store.saved['cfg-1'], isNotNull);
      expect(store.saved['cfg-1']!.username, 'alice');
      expect(store.saved['cfg-1']!.password, 'secret');

      final persisted = repo.webDavConfigs;
      expect(persisted, hasLength(1));
      expect(persisted.single.id, 'cfg-1');
      expect(persisted.single.username, isEmpty);
      expect(persisted.single.password, isEmpty);
      // 非敏感字段必须保真，迁移不能顺手改 URL 或名称。
      expect(persisted.single.name, '我的网盘');
      expect(persisted.single.url, 'https://dav.example.com/dav/');
      expect(persisted.single.remotePath, '/poemath/');
    });

    test('持久化串里真的不含明文口令', () async {
      useStore();
      await _seedRawConfigs([_plaintextConfig(password: 'p@ssw0rd-哨兵')]);

      await repo.migratePlaintextWebDavCredentials();

      expect(_rawHiveJson(), isNot(contains('p@ssw0rd-哨兵')));
      expect(_rawHiveJson(), isNot(contains('alice')));
    });

    test('安全存储写入抛错 → Hive 值保持不变', () async {
      useStore(failWrites: true);
      await _seedRawConfigs([_plaintextConfig()]);
      final before = _rawHiveJson();

      // 迁移自身吞掉逐条失败，不应向上抛。
      await repo.migratePlaintextWebDavCredentials();

      expect(store.saved, isEmpty);
      expect(_rawHiveJson(), before);
      // 明文仍可读，用户数据没丢 —— 只是这一轮没修好。
      expect(repo.webDavConfigs.single.password, 'secret');
    });

    test('部分失败：成功的置空，失败的保留原值', () async {
      // 用「写第二条才抛」的存储，验证逐条独立而非整批回滚。
      final partial = _FailOnSecondStore();
      repo = SettingsRepository(credentialStore: partial);
      await _seedRawConfigs([
        _plaintextConfig(id: 'ok', username: 'u1', password: 'p1'),
        _plaintextConfig(id: 'boom', username: 'u2', password: 'p2'),
      ]);

      await repo.migratePlaintextWebDavCredentials();

      final byId = {for (final c in repo.webDavConfigs) c.id: c};
      expect(byId['ok']!.password, isEmpty, reason: '写成功的那条应已置空');
      expect(byId['boom']!.password, 'p2', reason: '写失败的那条应保留明文');
      expect(partial.saved.keys, ['ok']);
    });

    test('凭据本就为空的配置 → 不写安全存储、不触发落盘', () async {
      useStore();
      await _seedRawConfigs([
        _plaintextConfig(username: '', password: ''),
      ]);
      final before = _rawHiveJson();

      await repo.migratePlaintextWebDavCredentials();

      expect(store.saved, isEmpty);
      // changed == false 时不应无谓重写 Hive（避免每次启动都产生写入）。
      expect(_rawHiveJson(), before);
    });

    test('无配置 / 坏 JSON → 静默返回，不抛', () async {
      useStore();

      await repo.migratePlaintextWebDavCredentials();
      expect(store.saved, isEmpty);

      await HiveBoxes.settings.put('webdav_configs', '{损坏');
      await repo.migratePlaintextWebDavCredentials();
      expect(store.saved, isEmpty);
    });

    test('多次调用幂等：第二次不再写安全存储', () async {
      useStore();
      await _seedRawConfigs([_plaintextConfig()]);

      await repo.migratePlaintextWebDavCredentials();
      final afterFirst = store.saved.length;
      await repo.migratePlaintextWebDavCredentials();

      expect(afterFirst, 1);
      expect(store.saved, hasLength(1));
    });
  });

  group('saveWebDavConfig 不落盘凭据（不变量）', () {
    test('写入后 Hive 中凭据为空，安全存储有值', () async {
      useStore();

      await repo.saveWebDavConfig(
        WebDavConfig(
          id: 'cfg-9',
          name: '新配置',
          url: 'https://dav.example.com/',
          username: 'bob',
          password: 'hunter2',
          remotePath: '/poemath/',
        ),
      );

      expect(store.saved['cfg-9']!.password, 'hunter2');
      expect(_rawHiveJson(), isNot(contains('hunter2')));
      expect(_rawHiveJson(), isNot(contains('bob')));
      expect(repo.webDavConfigs.single.password, isEmpty);
    });

    test('读取时从安全存储重新注入凭据', () async {
      useStore();
      await repo.saveWebDavConfig(
        WebDavConfig(
          id: 'cfg-9',
          name: '新配置',
          url: 'https://dav.example.com/',
          username: 'bob',
          password: 'hunter2',
          remotePath: '/poemath/',
        ),
      );

      // 传入的是「不含凭据」的配置（Hive 中实际持久化的形状），
      // 凭据由该方法从安全存储重新注入。
      final loaded = await repo.loadWebDavConfigWithCredentials(
        WebDavConfig(
          id: 'cfg-9',
          name: '新配置',
          url: 'https://dav.example.com/',
          username: '',
          password: '',
          remotePath: '/poemath/',
        ),
      );

      expect(loaded.username, 'bob');
      expect(loaded.password, 'hunter2');
    });
  });
}

/// 第一次写入成功、后续抛错 —— 用于验证逐条独立处理。
final class _FailOnSecondStore extends SecureCredentialStore {
  _FailOnSecondStore() : super(storage: const _InertSecureStorage());

  final Map<String, ({String username, String password})> saved = {};
  var _calls = 0;

  @override
  Future<void> saveWebDavCredentials({
    required String configId,
    required String username,
    required String password,
  }) async {
    _calls++;
    if (_calls > 1) throw StateError('模拟第二条写入失败');
    saved[configId] = (username: username, password: password);
  }
}
