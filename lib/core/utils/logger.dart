// lib/core/utils/logger.dart
//
// 层级：core/utils
// 职责：日志的统一入口。禁止业务代码直接使用 print()，一律走 AppLogger。
//
// 双通道：
//   * `kDebugMode` 下走 debugPrint（本地开发可见）。
//   * `w` / `e` 额外写入 [DiagnosticBuffer] 内存环形缓冲 —— **debug 与
//     release 都写**，这样 release 崩溃有落脚点，而单测可在本地（debug）
//     覆盖上限/scrub 行为，无需切 release 模式跑测试。
//   * `d` 不写缓冲（量太大）。

import 'package:flutter/foundation.dart';

import 'package:poemath/core/services/diagnostics/diagnostic_buffer.dart';

class AppLogger {
  const AppLogger._();

  /// 常规调试日志。**不写诊断缓冲**。
  static void d(Object? message, {String tag = 'PoeMath'}) {
    if (kDebugMode) {
      debugPrint('[$tag][D] $message');
    }
  }

  /// 警告日志。
  static void w(Object? message, {String tag = 'PoeMath'}) {
    if (kDebugMode) {
      debugPrint('[$tag][W] $message');
    }
    DiagnosticBuffer.instance.record(level: 'W', tag: tag, message: message);
  }

  /// 错误日志。
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
    DiagnosticBuffer.instance.record(
      level: 'E',
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
