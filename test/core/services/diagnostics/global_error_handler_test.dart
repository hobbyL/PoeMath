// test/core/services/diagnostics/global_error_handler_test.dart
//
// 全局错误处理挂载契约测试（10-18-security-hardening 问题 5 的 A 项）。
//
// 关键回归：`FlutterError.onError` 内**不得**调用 `FlutterError.reportError`。
// reportError 在 catch 到异常时会 `onError.call` 调回本函数 —— 同步错误即
// 无限递归（实测 StackOverflowError）。本文件是这个坑的守卫。
//
// 断言有咬合力：把实现改回 `reportError(details)` 时，第一条用例必须变红。

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/diagnostics/diagnostic_buffer.dart';
import 'package:poemath/main.dart';

void main() {
  late FlutterExceptionHandler? previous;

  setUp(() {
    previous = FlutterError.onError;
    DiagnosticBuffer.instance = DiagnosticBuffer();
    installGlobalErrorHandlers();
  });

  tearDown(() {
    FlutterError.onError = previous;
  });

  test('同步 FlutterError 只入缓冲一次且不递归栈溢出', () {
    // 若实现里出现 reportError(details)，此调用会抛 StackOverflowError，
    // `returnsNormally` 立即变红。
    expect(
      () => FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('probe-boom'),
          stack: StackTrace.fromString('PROBE-STACK'),
        ),
      ),
      returnsNormally,
    );

    final records = DiagnosticBuffer.instance.snapshot();
    expect(records, hasLength(1));
    expect(records.single.level, 'E');
    expect(records.single.tag, 'FlutterError');
    expect(records.single.message, contains('probe-boom'));
    expect(records.single.stackTrace, contains('PROBE-STACK'));
  });

  test('PlatformDispatcher 未捕获异步错误入缓冲并标记已处理', () {
    final handler = PlatformDispatcher.instance.onError;
    expect(handler, isNotNull);

    final handled = handler!(StateError('async-boom'), StackTrace.current);
    expect(handled, isTrue, reason: '返回 true 表示已处理，不终止应用');

    final records = DiagnosticBuffer.instance.snapshot();
    // 两条：handler 直接 record 一条，`AppLogger.e` 再记一条（双通道）。
    expect(records, isNotEmpty);
    expect(records.every((r) => r.level == 'E'), isTrue);
    expect(records.any((r) => r.tag == 'Uncaught'), isTrue);
    expect(records.first.message, contains('async-boom'));
  });
}
