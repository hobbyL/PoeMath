// lib/main.dart
//
// 应用入口。职责：
//   1. 确保 Flutter binding 初始化。
//   2. 立即启动 Flutter UI。
//   3. 由 AppBootstrap 初始化 Hive，并在失败时提供重试。

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/app_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AppBootstrap()));
}
