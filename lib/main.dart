// lib/main.dart
//
// 应用入口。职责：
//   1. 确保 Flutter binding 初始化。
//   2. 挂载全局错误处理（崩溃进诊断缓冲 + 日志）。
//   3. 立即启动 Flutter UI。
//   4. 由 AppBootstrap 初始化 Hive，并在失败时提供重试。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/app_bootstrap.dart';
import 'package:poemath/core/services/diagnostics/diagnostic_buffer.dart';
import 'package:poemath/core/utils/logger.dart';

/// 挂载全局错误处理，让 release 包的未捕获异常进入诊断缓冲。
///
/// **不加 `runZonedGuarded`**：Flutter 3.x 的 binding 已接管 zone 层错误，
/// 再套一层会让异步错误被记两次，且与 `PlatformDispatcher.instance.onError`
/// 职责重叠。实测依据见 10-18-security-hardening design.md §5.1。
void installGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    DiagnosticBuffer.instance.record(
      level: 'E',
      tag: 'FlutterError',
      message: details.exceptionAsString(),
      stackTrace: details.stack,
    );
    // 必须内联 [FlutterError.dumpErrorToConsole]，**不能**调
    // `FlutterError.reportError(details)`：后者在 catch 到自身异常时会
    // `inspect(details).onError.call(details)` 调回本函数，同步错误即无限递归
    // （实测 StackOverflowError）。`dumpErrorToConsole` 是框架默认
    // `presentError` 的落点，语义等价且不再回调 onError。
    FlutterError.dumpErrorToConsole(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    DiagnosticBuffer.instance.record(
      level: 'E',
      tag: 'Uncaught',
      message: error,
      error: error,
      stackTrace: stack,
    );
    AppLogger.e('未捕获的异步异常', tag: 'Uncaught', error: error, stackTrace: stack);
    return true; // 已处理，不终止应用
  };
}

/// 将随应用打包的音效署名加入「关于 → 开源许可」。
/// 注册时不读文件，打开许可页后才加载正文。
void registerAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, path) in [
      ('童趣答题语音 — 雨多多', 'assets/sounds/LICENSE-child-voice.txt'),
      ('完成提示音 — Kenney', 'assets/sounds/LICENSE-completion.txt'),
    ]) {
      final text = await rootBundle.loadString(path);
      yield LicenseEntryWithLineBreaks([name], text);
    }
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installGlobalErrorHandlers();
  registerAssetLicenses();
  runApp(const ProviderScope(child: AppBootstrap()));
}
