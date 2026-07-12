// test/helpers/hive_test_helper.dart
//
// 测试辅助：初始化 Hive 到临时目录并预填数据版本，
// 使 DataBootstrap.ensureInitialized() 跳过 asset 导入。

import 'dart:io';

import 'package:hive/hive.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/hive_registrar.dart';

Directory? _tempDir;

/// 在测试 setUp 中调用。初始化 Hive 到临时目录并预填 data_version。
Future<void> setUpHiveForTesting() async {
  _tempDir = await Directory.systemTemp.createTemp('hive_test_');
  Hive.init(_tempDir!.path);
  registerHiveAdapters();
  await HiveBoxes.init();

  // 预填数据版本，跳过 DataBootstrap asset 导入
  await HiveBoxes.meta.put(
    HiveKeys.metaDataVersion,
    AppConstants.dataVersion,
  );
}

/// 在测试 tearDown 中调用。关闭 Hive 并清理临时目录。
Future<void> tearDownHiveForTesting() async {
  await HiveBoxes.close();
  if (_tempDir != null && _tempDir!.existsSync()) {
    _tempDir!.deleteSync(recursive: true);
  }
  _tempDir = null;
}
