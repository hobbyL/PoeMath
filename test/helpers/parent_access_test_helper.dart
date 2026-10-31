import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:poemath/core/services/parent_access_service.dart';

const testParentPin = '246810';

/// 管理功能测试显式建立真实 PIN；不要改变 Hive 通用 fixture 的默认锁定状态。
/// 在 setUp 或 tester.runAsync 中调用，可一并保留该用例的合成凭据。
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
  return access.configure(testParentPin);
}

void lockParentForTesting() => ParentAccessService.instance.lock();
