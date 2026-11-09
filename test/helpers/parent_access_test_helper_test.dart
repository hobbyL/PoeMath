import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';

import 'hive_test_helper.dart';
import 'parent_access_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('普通 Hive fixture 默认锁定，准备后仍通过真实 PIN 校验', () async {
    final access = ParentAccessService.instance;
    expect(access.enabled, isFalse);
    expect(access.isUnlocked, isFalse);
    expect(access.assertAllowed, throwsA(isA<ParentAccessDenied>()));

    await unlockParentForTesting();
    expect(access.isUnlocked, isTrue);
    access.lock();
    expect(await access.authenticate('000000'), isFalse);
    expect(access.assertAllowed, throwsA(isA<ParentAccessDenied>()));
    expect(await access.authenticate(testParentPin), isTrue);
  });

  test('重复准备清除旧失败次数和凭据，旧授权失效且恢复码仍只可用一次', () async {
    final access = ParentAccessService.instance;
    final store = SecureCredentialStore();
    final firstRecovery = await unlockParentForTesting(
      credentials: {'old_test_credential': 'old'},
    );
    final oldAuthorization = access.captureAuthorization();
    access.lock();
    expect(await access.authenticate('000000'), isFalse);
    final changed = jsonDecode((await store.readParentProtection())!) as Map;
    expect(changed['failures'], 1);

    final nextRecovery = await unlockParentForTesting(
      credentials: {'new_test_credential': 'new'},
    );
    expect(access.isUnlocked, isTrue);
    expect(oldAuthorization, throwsA(isA<ParentAccessDenied>()));
    expect(await store.readRawSecret('old_test_credential'), isNull);
    expect(await store.readRawSecret('new_test_credential'), 'new');
    final fresh = jsonDecode((await store.readParentProtection())!) as Map;
    expect(fresh['failures'], 0);
    expect(fresh.containsKey('blockedUntil'), isFalse);
    expect(nextRecovery, firstRecovery);

    access.lock();
    expect(await access.authenticate(nextRecovery, recovery: true), isTrue);
    expect(access.enabled, isFalse);
    expect(access.isUnlocked, isFalse);
    expect(await access.authenticate(nextRecovery, recovery: true), isFalse);

    // 恢复码被消费也不能修改缓存的初始记录，下个 fixture 可独立建立授权。
    await unlockParentForTesting();
    expect(access.isUnlocked, isTrue);
    expect(access.needsResetNotice, isFalse);
  });
}
