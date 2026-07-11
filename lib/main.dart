// lib/main.dart
//
// 应用入口。职责：
//   1. 确保 Flutter binding 初始化。
//   2. 初始化 Hive（后续 Phase 2 会开始定义 Box）。
//   3. 用 ProviderScope 包裹根 App。

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:poemath/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const ProviderScope(child: App()));
}
