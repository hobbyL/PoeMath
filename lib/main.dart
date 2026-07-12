// lib/main.dart
//
// 应用入口。职责：
//   1. 确保 Flutter binding 初始化。
//   2. 初始化 Hive + 注册 TypeAdapter + 打开所有 Box。
//   3. 用 ProviderScope 包裹根 App。

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:poemath/app.dart';
import 'package:poemath/data/hive/hive_registrar.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化 Hive
  await Hive.initFlutter();

  // 2. 注册所有 TypeAdapter
  registerHiveAdapters();

  // 3. 打开所有 Box
  await HiveBoxes.init();

  // 4. 启动 App
  runApp(const ProviderScope(child: App()));
}
