// test/helpers/hive_test_helper.dart
//
// 测试辅助：初始化 Hive 到临时目录并预填数据版本，
// 使 DataBootstrap.ensureInitialized() 跳过 asset 导入。

import 'dart:async';
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
  await HiveBoxes.meta.put(HiveKeys.metaDataVersion, AppConstants.dataVersion);

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
/// 测试体中的写入完成回调依赖 fake zone；离开测试体后无法继续 pump，
/// 所以必须先调用 [drainHiveWritesForTesting]，再由 tearDown 关闭数据库。
Future<void> tearDownHiveForWidgetTesting() async {
  await HiveBoxes.close();
  _cleanupTempDir();
}

/// 在 widget 测试写入后调用，等待所有已打开的项目 Box 完成刷盘。
///
/// Hive 的写链包含在 fake zone 创建的 Future；只在 runAsync 内等待
/// flush 会把完成回调堵在 fake 微任务队列中，每次都耗尽 5 秒超时。
/// 在真实 zone 发起刷盘但不阻塞等待，交替推进真实 IO 与 fake 微任务。
/// 写链末尾的 Future 也必须属于真实 zone，才能在测试结束后正常 close。
/// 不使用 pumpAndSettle，页面上的持续动画不影响此处的完成判断。
Future<void> drainHiveWritesForTesting(WidgetTester tester) async {
  final boxes = <BoxBase<dynamic>>[
    HiveBoxes.poems,
    HiveBoxes.authors,
    HiveBoxes.formulas,
    HiveBoxes.poemProgress,
    HiveBoxes.poemFavorites,
    HiveBoxes.reviewSchedules,
    HiveBoxes.mathMistakes,
    HiveBoxes.mathSessions,
    HiveBoxes.formulaFavorites,
    HiveBoxes.achievements,
    HiveBoxes.checkIns,
    HiveBoxes.userStats,
    HiveBoxes.challengeRecords,
    HiveBoxes.learningActivities,
    HiveBoxes.llmProblems,
    HiveBoxes.conversations,
    HiveBoxes.messages,
    HiveBoxes.pictureStoryPractice,
    HiveBoxes.settings,
    HiveBoxes.meta,
  ].where((box) => box.isOpen);
  var completed = false;
  Object? failure;
  StackTrace? failureStack;
  await tester.runAsync(() async {
    unawaited(
      Future.wait(boxes.map((box) => box.flush())).then(
        (_) => completed = true,
        onError: (Object error, StackTrace stack) {
          failure = error;
          failureStack = stack;
          completed = true;
        },
      ),
    );
  });
  final stopwatch = Stopwatch()..start();
  while (!completed && stopwatch.elapsed < _drainTimeout) {
    await tester.pump();
    if (!completed) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  if (!completed) {
    throw TimeoutException('Hive 写入在 $_drainTimeout 内未完成', _drainTimeout);
  }
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
