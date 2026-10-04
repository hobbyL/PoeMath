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

  test('白名单键常量与 SecureCredentialStore 存储键一致', () {
    expect(kBackupCredentialKeys, contains('tencent_asr_secret_id'));
    expect(kBackupCredentialKeys, contains('tencent_asr_secret_key'));
    expect(kBackupCredentialKeys, contains('worker_tts_api_key'));
  });
}
