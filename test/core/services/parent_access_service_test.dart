import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

import '../../helpers/hive_test_helper.dart';

class _Store extends SecureCredentialStore {
  String? record;
  bool failRead = false;
  bool failSaveAfterMutation = false;
  bool failDelete = false;
  Completer<void>? holdRead;
  Completer<void>? holdNextSave;
  Completer<void>? saveEntered;
  @override
  Future<String?> readParentProtection() async {
    await holdRead?.future;
    if (failRead) throw StateError('secure read unavailable');
    return record;
  }

  @override
  Future<void> saveParentProtection(String value) async {
    record = value;
    final gate = holdNextSave;
    holdNextSave = null;
    saveEntered?.complete();
    saveEntered = null;
    await gate?.future;
    if (failSaveAfterMutation) {
      failSaveAfterMutation = false;
      throw StateError('save failure after mutation');
    }
  }

  @override
  Future<void> deleteParentProtection() async {
    if (failDelete) throw StateError('delete unavailable');
    record = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late ParentAccessService access;
  var now = DateTime(2026, 10, 16);
  setUp(() async {
    await setUpHiveForTesting();
    now = DateTime(2026, 10, 16);
    store = _Store();
    access = ParentAccessService(store: store, clock: () => now);
  });
  tearDown(() async {
    access.dispose();
    await tearDownHiveForTesting();
  });

  test('默认关闭，PIN与恢复码仅存盐化摘要且不在Hive', () async {
    expect(access.enabled, isFalse);
    expect(access.isUnlocked, isTrue);
    await expectLater(access.configure('12345'), throwsFormatException);
    final recovery = await access.configure('123456');
    final record = jsonDecode(store.record!) as Map<String, dynamic>;
    expect(record['salt'], isNotEmpty);
    expect(record['digest'], isNot(contains('123456')));
    expect(store.record, isNot(contains(recovery.replaceAll('-', ''))));
    expect(HiveBoxes.settings.values.join(), isNot(contains('123456')));
    access.lock();
    expect(access.isUnlocked, isFalse);
    expect(await access.authenticate('999999'), isFalse);
    expect(await access.authenticate('123456'), isTrue);
    now = now.add(ParentAccessService.unlockDuration);
    expect(access.isUnlocked, isFalse);
  });

  test('后台事件使进行中的验证失效，不能在await后重新解锁', () async {
    await access.configure('123456');
    access.lock();
    store.holdRead = Completer<void>();
    final authentication = access.authenticate('123456');
    await Future<void>.delayed(Duration.zero);
    access.didChangeAppLifecycleState(AppLifecycleState.paused);
    store.holdRead!.complete();
    expect(await authentication, isFalse);
    expect(access.isUnlocked, isFalse);
  });

  test('连续错误有持久等待时间，一次性恢复码关闭保护且不能重用', () async {
    final code = await access.configure('123456');
    access.lock();
    for (var index = 0; index < 5; index++) {
      expect(await access.authenticate('000000'), isFalse);
    }
    await expectLater(access.authenticate('123456'), throwsStateError);
    now = now.add(const Duration(seconds: 31));
    expect(
        await access.authenticate(code.toLowerCase(), recovery: true), isTrue,);
    expect(access.enabled, isFalse);
    expect(store.record, isNull);
    expect(await access.authenticate(code, recovery: true), isFalse);
  });

  test('配置写失败补回旧摘要；删除故障不留下启用却无摘要的死锁', () async {
    await access.configure('123456');
    final old = store.record;
    store.failSaveAfterMutation = true;
    await expectLater(access.configure('654321'), throwsStateError);
    expect(store.record, old);
    expect(access.enabled, isTrue);
    store.failDelete = true;
    await access.disable();
    expect(access.enabled, isFalse);
    expect(access.isUnlocked, isTrue);
  });

  test('保存新PIN期间进入后台会补偿原摘要，不提交失效授权', () async {
    await access.configure('123456');
    final old = store.record;
    final entered = Completer<void>();
    final release = Completer<void>();
    store.saveEntered = entered;
    store.holdNextSave = release;
    final changing = access.configure('654321');
    final outcome = expectLater(changing, throwsA(isA<ParentAccessDenied>()));
    await entered.future;
    access.didChangeAppLifecycleState(AppLifecycleState.paused);
    release.complete();
    await outcome;
    expect(store.record, old);
    expect(access.enabled, isTrue);
    expect(access.isUnlocked, isFalse);
  });

  test('系统迁移摘要真实缺项时重设并提示，安全读取异常保持锁定', () async {
    await HiveBoxes.settings.put('parent_protection_enabled', true);
    store.failRead = true;
    await expectLater(access.initialize(), throwsStateError);
    expect(access.enabled, isTrue);
    expect(access.isUnlocked, isFalse);
    expect(access.needsResetNotice, isFalse);
    store.failRead = false;
    await access.initialize();
    expect(access.enabled, isFalse);
    expect(access.isUnlocked, isTrue);
    expect(access.needsResetNotice, isTrue);
  });
}
