// lib/core/utils/logger.dart
//
// 层级：core/utils
// 职责：调试输出的统一入口。Phase 0 只做 debugPrint 包装。
//       禁止业务代码直接使用 print()，一律走 AppLogger。

import 'package:flutter/foundation.dart';

class AppLogger {
  const AppLogger._();

  /// 常规调试日志
  static void d(Object? message, {String tag = 'PoeMath'}) {
    if (kDebugMode) {
      debugPrint('[$tag][D] $message');
    }
  }

  /// 警告日志
  static void w(Object? message, {String tag = 'PoeMath'}) {
    if (kDebugMode) {
      debugPrint('[$tag][W] $message');
    }
  }

  /// 错误日志
  static void e(
    Object? message, {
    String tag = 'PoeMath',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      debugPrint('[$tag][E] $message');
      if (error != null) debugPrint('  cause: $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    }
  }
}
