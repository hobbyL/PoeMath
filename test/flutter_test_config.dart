// test/flutter_test_config.dart
//
// flutter_test 会在运行任何测试前自动加载本文件（同目录或其任意祖先目录，
// 名为 `flutter_test_config.dart`），因此这里是给**全仓测试**统一施加约束的
// 唯一入口。
//
// 为什么需要它：`TestWidgetsFlutterBinding.defaultTestTimeout` 的默认值是
// **10 分钟**（见 flutter_test/lib/src/binding.dart）。本仓存在若干 widget
// 测试会挂进"永不结束"状态（见
// .trellis/tasks/10-18-preexisting-test-failures/research/timeout-hang-diagnosis.md），
// 于是每次触发都要空等 10 分钟才失败，而 `flutter test` 要等所有测试结束才
// 汇总 —— 一次全量因此从 ~5 分钟膨胀到 ~15 分钟。
//
// 压到 30 秒后，同一批挂起会在 30 秒内明确失败，而不是拖垮整轮运行。
// 本仓正常 widget 测试多在 1-5 秒内完成，30 秒对它们没有影响。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// 单个测试的超时上限。
///
/// 30 秒的依据：正常 widget 测试耗时多在 1-5 秒；挂起类测试的失败模式是
/// "永不结束"，任何有限值都能捕获它。取 30 秒而非更小，是为了给 CI 上较慢
/// 的机器、以及含真实异步（Hive 打开、静态数据导入）的测试留出余量。
///
/// 类型是 `Timeout`（flutter_test 自 widget_tester.dart 转发 test_api 的定义），
/// 不是 `Duration` —— `defaultTestTimeout` 期望前者。
final Timeout _testTimeout = Timeout(Duration(seconds: 30));

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // 必须在 testMain() 之前设置：该值在测试注册时被读取。
  //
  // 用具体子类 `AutomatedTestWidgetsFlutterBinding`：`defaultTestTimeout` 的
  // setter 只定义在它上面（基类 `TestWidgetsFlutterBinding` 只有 getter）。
  // 普通 `flutter test` 走的就是 Automated 绑定；集成测试走 Live 绑定，
  // 不受本文件影响（其 defaultTestTimeout 恒为 `Timeout.none`）。
  //
  // 影响范围：所有 `testWidgets` 未显式传 `timeout:` 的用例。
  // 需要更长耗时的测试（集成/流程类）应在自身显式声明
  // `testWidgets(..., timeout: Timeout(Duration(minutes: N)))` 覆盖。
  AutomatedTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout =
      _testTimeout;

  await testMain();
}
