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

  test('载荷键全部不识别：抛错且文案指向版本、给出自救出路', () async {
    final node = await encryptCredentials({'bogus_key': 'value'}, 'p');
    await expectLater(
      decryptCredentials(node, 'p'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('更高版本'), contains('留空口令')),
        ),
      ),
    );
  });

  test('载荷含未识别键：跳过未知键、照常返回已知键（向前兼容）', () async {
    // 跨版本恢复的核心路径：更高版本新增了凭据键，旧版本必须仍能用
    // 自己认识的那部分。此前的实现对任一未知键直接抛 FormatException，
    // 而解密发生在 `_doRestore` 之前，异常会让**整个恢复**失败 ——
    // 用户的诗词进度、错题本、复习计划全都恢复不了。
    //
    // 未知键不可能来自篡改：走到白名单校验时 AES-GCM 认证已经通过，
    // 能产出合法密文的人必须知道口令。
    final node = await encryptCredentials(
      {
        kCredKeyTencentSecretId: 'id-1',
        kCredKeyTencentSecretKey: 'key-1',
        'future_vendor_api_key': 'from-newer-version',
      },
      '正确口令-123',
    );

    final restored = await decryptCredentials(node, '正确口令-123');

    expect(
      restored,
      <String, String>{
        kCredKeyTencentSecretId: 'id-1',
        kCredKeyTencentSecretKey: 'key-1',
      },
      reason: '已知键必须照常恢复，未知键静默跳过',
    );
    expect(
      restored.containsKey('future_vendor_api_key'),
      isFalse,
      reason: '未知键不得进入恢复结果（否则会被写进意料之外的位置）',
    );
  });

  test('白名单键锁定：内容精确且每个键都能完整往返', () async {
    // 恒真回归：本用例原先是 `expect(kBackupCredentialKeys, contains('...'))`
    // 三连 —— 把常量跟自己的字面量比，等于「断言常量等于常量」。标题声称
    // 「与 SecureCredentialStore 存储键一致」，但那个说法本身就是概念错误：
    // 这些是**备份 JSON 内部**的 payload 键，恢复端经
    // `saveTencentAsrCredentials` 等方法写安全存储、不按键直写，
    // 两套名字同名纯属巧合，不存在「必须一致」的契约。
    //
    // 真实风险在于备份子系统**内部**的副本漂移：生产端
    // `_exportCredentials` 若写入白名单外的键，该键在恢复端会被跳过，
    // 凭据静默丢失。现已把三处字面量收敛到 backup_credentials_cipher.dart
    // 的命名常量，这里负责锁定常量表本身。

    // 1) 精确锁定白名单内容：任何增删改都必须同步改这里。
    expect(kBackupCredentialKeys, <String>[
      kCredKeyTencentSecretId,
      kCredKeyTencentSecretKey,
      kCredKeyWorkerTtsApiKey,
      kCredKeyLlmApiKey,
      kCredKeyLlmApiKeyHint,
      kCredKeyLlmProviderKeys,
    ]);
    // 2) 常量的字面值也锁定：改动会让已发布版本导出的备份读不出对应项。
    expect(kBackupCredentialKeys, <String>[
      'tencent_asr_secret_id',
      'tencent_asr_secret_key',
      'worker_tts_api_key',
      'llm_api_key',
      'llm_api_key_hint',
      'llm_provider_keys',
    ]);

    // 3) 每个白名单键都必须能真正往返：防止「加进白名单但密码学层处理
    //    不了」的半成品键 —— 那种键一旦被生产端写入就使凭据不可恢复。
    final payload = <String, String>{
      for (final key in kBackupCredentialKeys) key: 'value-of-$key',
    };
    final node = await encryptCredentials(payload, '正确口令-123');
    final restored = await decryptCredentials(node, '正确口令-123');

    expect(restored, payload, reason: '全量白名单键必须无损往返');
  });
}
