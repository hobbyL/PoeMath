// test/helpers/hive_test_helper.dart
//
// 测试辅助：初始化 Hive 到临时目录并预填数据版本，
// 使 DataBootstrap.ensureInitialized() 跳过 asset 导入。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/hive_registrar.dart';
import 'package:poemath/data/repositories/poem_repository.dart';

Directory? _tempDir;

/// 在测试 setUp 中调用。初始化 Hive 到临时目录并预填 data_version。
Future<void> setUpHiveForTesting() async {
  _tempDir = await Directory.systemTemp.createTemp('hive_test_');
  Hive.init(_tempDir!.path);
  registerHiveAdapters();
  await HiveBoxes.init();

  // 诗词索引是进程级静态字段（见 `PoemRepository` 的静态化说明），
  // 会跨测试用例残留上一个用例的数据。此处复位，使每个用例都从
  // 「索引未构建」的干净状态开始。
  PoemRepository.resetIndices();

  // 预填数据版本，跳过 DataBootstrap asset 导入
  await HiveBoxes.meta.put(
    HiveKeys.metaDataVersion,
    AppConstants.dataVersion,
  );

  await HiveBoxes.meta.put('content_revision', AppConstants.contentRevision);

  // 标记已完成引导，跳过 Onboarding 页面
  await HiveBoxes.settings.put('has_onboarded', true);
}

/// 在测试 tearDown 中调用。关闭 Hive 并清理临时目录。
Future<void> tearDownHiveForTesting() async {
  await HiveBoxes.close();
  _cleanupTempDir();
}

/// 在 **widget 测试**的 tearDown 中调用。关闭 Hive 并清理临时目录。
///
/// 与 [tearDownHiveForTesting] 的唯一区别：适用于 `testWidgets` 用例。
/// 前提是测试体末尾调用过 [drainHiveWritesForTesting]。
///
/// 为什么必须先在测试体里排空写链：`Box.put` 不是同步落盘，它把写帧挂到
/// Hive 内部 `ReadWriteSync` 的**写链**上排队（`storage_backend_vm.dart` →
/// `read_write_sync.dart`）。而 `Hive.close()` 走的是同一条链上的
/// `syncReadWrite(_closeInternal)` —— 必须排在这些写任务**之后**。
///
/// 在 `testWidgets` 的 **fake 时钟**下，写任务的完成回调排不到执行，
/// 于是 `close()` 永远等不到前面的写任务让出链，30s 后超时。实测：
///
/// - `testWidgets` + 只 `box.get(...)`（无写）→ `close()` 正常返回
/// - `testWidgets` + 一次 `box.put(...)`        → `close()` 卡死 30s
///
/// 注意：卡点只在「测试体执行过写操作」，与 `Box.watch().listen` 订阅、
/// `provider` 的 `ref.onDispose` 均无关（这两项已分别实验排除）。
///
/// **在这里刷盘没用**：`flush()` 自己也走写链，同样排不动。
/// 必须回到测试体里，用 [drainHiveWritesForTesting] 借 `runAsync`
/// 的真实时钟把链推一下 —— 只是「进入过一次真实时钟」就足以解开整条链，
/// 此后 [tearDownHiveForWidgetTesting] 的 `close()` 即可正常返回。
///
/// 纯 `test(` 用例没有 fake 时钟，继续用 [tearDownHiveForTesting] 即可。
Future<void> tearDownHiveForWidgetTesting() async {
  await HiveBoxes.close();
  _cleanupTempDir();
}

/// 在 **widget 测试体末尾**调用，排空 Hive 的写链，使 tearDown 的
/// `Hive.close()` 能正常返回。
///
/// 原理：`tester.runAsync` 把回调切到**真实时钟**下执行。真实时钟一跑起来，
/// 挂在 `ReadWriteSync` 写链上的写任务就能跑到完成回调，链被让出；
/// 之后 tearDown 里排在链尾的 `close()` 才排得动。
///
/// 调用位置必须是**测试体的最后一步**——写操作之后、`testWidgets` 返回之前。
///
/// 注意 `flush()` 自身**仍可能超时**（它同样排在写链上），这**不影响**
/// 后续 `close()`：超时被吞掉即可，解链的效果已经达成。实测输出：
///
/// ```
/// >>> Y2 flushing meta
/// >>>   !!! meta flush timeout      ← flush 本身超时
/// >>> TD enter
/// >>> TD done                       ← close() 正常返回
/// ```
Future<void> drainHiveWritesForTesting(WidgetTester tester) async {
  await tester.runAsync(() async {
    try {
      await HiveBoxes.meta.flush().timeout(_drainTimeout);
    } on Object {
      // 含 TimeoutException：flush 排不动属预期，解链效果已达成。
    }
  });
}

/// 单次排空的上限，纯粹兜底，避免真实时钟下意外长时间占用。
const Duration _drainTimeout = Duration(seconds: 5);

void _cleanupTempDir() {
  if (_tempDir != null && _tempDir!.existsSync()) {
    _tempDir!.deleteSync(recursive: true);
  }
  _tempDir = null;
  // 静态索引指向已删除的临时 box，保留会污染后续用例。
  PoemRepository.resetIndices();
}
