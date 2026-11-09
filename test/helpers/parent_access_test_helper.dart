import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

const testParentPin = '246810';

// 只缓存由真实 configure 生成的不可变初始记录，不共享存储或解锁状态。
// 管理功能测试无须每次重新派生 PIN + 恢复码两个摘要；密码设置流程由
// parent_access_service_test / settings_parent_access_test 单独覆盖。
({String record, String recovery})? _initialProtection;

/// 管理功能测试显式建立真实 PIN；不改变 Hive 通用 fixture 的默认锁定状态。
/// 在 setUp 或 tester.runAsync 中调用，可一并保留该用例的合成凭据。
/// 首次真实配置，后续用例安装相同初始记录并通过真实 authenticate 解锁。
Future<String> unlockParentForTesting({
  Map<String, String> credentials = const {},
}) async {
  FlutterSecureStorage.setMockInitialValues(
    Map<String, String>.from(credentials),
  );
  final access = ParentAccessService.instance;
  access.didChangeAppLifecycleState(AppLifecycleState.resumed);
  await access.initialize();
  access.lock();
  final store = SecureCredentialStore();
  final initial = _initialProtection;
  if (initial == null || credentials.containsKey('parent_protection')) {
    final recovery = await access.configure(testParentPin);
    final record = await store.readParentProtection();
    if (record == null) throw StateError('测试 PIN 配置未保存');
    _initialProtection = (record: record, recovery: recovery);
    return recovery;
  }
  await store.saveParentProtection(initial.record);
  await HiveBoxes.settings.put('parent_protection_enabled', true);
  await HiveBoxes.settings.delete('parent_protection_reset_notice');
  if (!await access.authenticate(testParentPin)) {
    throw StateError('测试 PIN 未通过真实验证');
  }
  return initial.recovery;
}

void lockParentForTesting() => ParentAccessService.instance.lock();
