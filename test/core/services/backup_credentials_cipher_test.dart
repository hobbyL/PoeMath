// test/core/services/backup_credentials_cipher_test.dart
//
// 备份凭据加密层纯函数测试：roundtrip、错口令、结构破坏、参数界、
// 随机性与明文不泄露。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_credentials_cipher.dart';

void main() {
  const payload = <String, String>{
    'tencent_asr_secret_id': 'AKID-demo-secret-id',
    'tencent_asr_secret_key': 'SK-demo-secret-key',
    'worker_tts_api_key': 'worker-tts-demo-key',
  };

  Future<Map<String, dynamic>> encrypt([String passphrase = '正确口令-123']) {
    return encryptCredentials(Map.of(payload), passphrase);
  }

  test('roundtrip：加密结构完整且同口令解密还原', () async {
    final node = await encrypt();

    final kdf = node['kdf'] as Map<String, dynamic>;
    expect(kdf['algorithm'], 'pbkdf2-sha256');
    expect(kdf['iterations'], 120000);
    expect(kdf['salt'], isA<String>());

    final cipherNode = node['cipher'] as Map<String, dynamic>;
    expect(cipherNode['algorithm'], 'aes-256-gcm');
    expect(cipherNode['nonce'], isA<String>());
    expect(cipherNode['ciphertext'], isA<String>());

    final restored = await decryptCredentials(node, '正确口令-123');
    expect(restored, payload);
  });

  test('密文形态不含明文凭据（AC6 加密层）', () async {
    final node = await encrypt();
    final serialized = jsonEncode(node);
    for (final value in payload.values) {
      expect(serialized, isNot(contains(value)));
    }
  });

  test('随机 salt/nonce：两次加密产生不同密文', () async {
    final first = await encrypt();
    final second = await encrypt();
    final firstCipher = (first['cipher'] as Map)['ciphertext'] as String;
    final secondCipher = (second['cipher'] as Map)['ciphertext'] as String;
    expect(firstCipher, isNot(secondCipher));
  });

  test('空载荷抛 ArgumentError', () async {
    await expectLater(
      encryptCredentials(const {}, 'p'),
      throwsArgumentError,
    );
  });

  test('错口令抛 FormatException 且消息含口令提示（AC2）', () async {
    final node = await encrypt('正确口令');
    await expectLater(
      decryptCredentials(node, '错误口令'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('口令'),
        ),
      ),
    );
  });

  test('密文被篡改抛 FormatException（GCM 认证）', () async {
    final node = await encrypt();
    final cipherNode = node['cipher'] as Map<String, dynamic>;
    final combined = base64Decode(cipherNode['ciphertext'] as String);
    combined[combined.length - 1] ^= 0x01; // 破坏末位（MAC 区域）
    cipherNode['ciphertext'] = base64Encode(combined);
    await expectLater(
      decryptCredentials(node, '正确口令-123'),
      throwsFormatException,
    );
  });

  test('缺少 kdf/cipher 节拒绝', () async {
    final node = await encrypt();
    node.remove('kdf');
    await expectLater(
      decryptCredentials(node, '正确口令-123'),
      throwsFormatException,
    );
  });

  test('KDF 算法不符拒绝', () async {
    final node = await encrypt();
    (node['kdf'] as Map)['algorithm'] = 'pbkdf2-md5';
    await expectLater(
      decryptCredentials(node, '正确口令-123'),
      throwsFormatException,
    );
  });

  test('iterations 超界拒绝（过小/过大）', () async {
    for (final iterations in [999, 10000001]) {
      final node = await encrypt();
      (node['kdf'] as Map)['iterations'] = iterations;
      await expectLater(
        decryptCredentials(node, '正确口令-123'),
        throwsFormatException,
        reason: 'iterations=$iterations 应被拒绝',
      );
    }
  });

  test('base64 损坏拒绝', () async {
    final node = await encrypt();
    (node['cipher'] as Map)['ciphertext'] = '!!!not-base64!!!';
    await expectLater(
      decryptCredentials(node, '正确口令-123'),
      throwsFormatException,
    );
  });

  test('nonce 长度不符拒绝', () async {
    final node = await encrypt();
    (node['cipher'] as Map)['nonce'] = base64Encode(List.filled(11, 1));
    await expectLater(
      decryptCredentials(node, '正确口令-123'),
      throwsFormatException,
    );
  });

  test('密文短于 nonce+mac 拒绝', () async {
    final node = await encrypt();
    (node['cipher'] as Map)['ciphertext'] = base64Encode(List.filled(16, 1));
    await expectLater(
      decryptCredentials(node, '正确口令-123'),
      throwsFormatException,
    );
  });

  test('载荷键不在白名单拒绝', () async {
    final node = await encryptCredentials({'bogus_key': 'value'}, 'p');
    await expectLater(
      decryptCredentials(node, 'p'),
      throwsFormatException,
    );
  });

  test('白名单键锁定：内容精确且每个键都能完整往返', () async {
    // 恒真回归：本用例原先是 `expect(kBackupCredentialKeys, contains('...'))`
    // 三连 —— 把常量跟自己的字面量比，等于「断言常量等于常量」。标题声称
    // 「与 SecureCredentialStore 存储键一致」，但全程没有引用过
    // SecureCredentialStore（它的键是私有的 `_tencentSecretIdKey` 等，
    // 测试引用不到），而且漏掉了 llm_api_key / llm_api_key_hint 两项。
    //
    // 真实风险：生产端 `BackupService._exportCredentials` 若写入一个不在
    // 白名单里的键，解密端 `backup_credentials_cipher.dart:135` 会
    // throw FormatException，**整个 credentials 节报废** —— 用户恢复备份后
    // 所有凭据静默丢失。所以这里改为两条有牙齿的断言。

    // 1) 精确锁定白名单内容：任何增删改都必须同步改这里，
    //    逼迫改动者回头确认另外三处副本（存储层私有常量、
    //    BackupService 生产端 :182-191、消费端 :424-444）。
    expect(kBackupCredentialKeys, <String>[
      'tencent_asr_secret_id',
      'tencent_asr_secret_key',
      'worker_tts_api_key',
      'llm_api_key',
      'llm_api_key_hint',
    ]);

    // 2) 每个白名单键都必须能真正往返：防止「加进白名单但密码学层处理
    //    不了」的半成品键 —— 那种键一旦被生产端写入就使备份不可恢复。
    final payload = <String, String>{
      for (final key in kBackupCredentialKeys) key: 'value-of-$key',
    };
    final node = await encryptCredentials(payload, '正确口令-123');
    final restored = await decryptCredentials(node, '正确口令-123');

    expect(restored, payload, reason: '全量白名单键必须无损往返');
  });
}
