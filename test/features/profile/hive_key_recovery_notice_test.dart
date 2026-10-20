// test/features/profile/hive_key_recovery_notice_test.dart
//
// G6 的闸门：密钥丢失降级后，用户**必须**看到提示，且**只看到一次**。
//
// 对应 `prd.md` 问题 8 验收 3（「清 secure storage 后不崩、空数据启动 +
// 可见提示」）与 `design.md` §7.4（「静默重建空 box 是数据丢失事故的伪装，
// 必须让用户知道发生了什么」）。
//
// ── 分层理由 ──────────────────────────────────────────────────────────
//
// 本文件刻意分两组，因为两类断言在 `flutter_test` 里代价完全不同：
//
// * 「读标记 / 清标记 / 幂等」是**纯逻辑**，用 `test` 写。`test` 不跑在
//   `fake_async` 里，可以自由 `await` Hive。写成 `testWidgets` 反而会踩坑：
//   `testWidgets` 体内 `await HiveBoxes.meta.put(...)` 永远等不到真实异步，
//   用例直接挂到 30 秒超时（不是断言失败，是挂住）。
//
// * 「标记为 true → 渲染出提示」是**纯渲染事实**，用 `testWidgets` 写。
//   只断言「提示出现了」，不断言清除 —— 清除涉及 fire-and-forget 写入，
//   要等真实异步落盘，而 `tester.runAsync` 会让真实时钟与 fake clock 交错，
//   把后续断言拖进不稳定状态（实测：`runAsync` 之后再 pump，标记状态与
//   预期错位）。清除语义已由上面的 `test` 组完整覆盖，不必在这里重测。
//
// ── widget 用例的两条写法约束（实测踩出来的）──────────────────────────
//
// ① **不要只 pump 一帧就断言。**
//    `ProfilePage` 的 body 是 `AnimatedPageBody`，用
//    `AnimateList(interval: 80ms)` 给每个子项排了 `Future.delayed` 入场动画。
//    只 pump 一帧时这些定时器仍 pending，框架会以「A Timer is still pending
//    even after the widget tree was disposed」判失败 —— 与被测逻辑无关。
//    用 `pump(Duration)` 真正推进 fake clock 把它跑完
//    （`pumpAndSettle` 不管 `Future.delayed` 排的定时器）。
//
// ② **必须 override `dayKeyProvider` 为静态值。**
//    `ProfilePage` 经 `userStatsProvider` / `streakProvider` 依赖它，而
//    `DayKeyNotifier.build` 会起一个 30 秒 `Timer.periodic`（前台跨午夜
//    失效）。这个 Timer 让 `tearDown` 里的 `HiveBoxes.close()` 之后清理
//    永远等不到，用例在**体已跑完**的情况下挂到超时。仓库已有
//    `staticDayKeyOverride()` 专治此症（同样被 `main_shell_test` 等使用）。
//
// ③ **提示为 true 的用例必须把整段包进 `tester.runAsync`。**
//    提示一渲染，`_HiveKeyRecoveredNotice` 的 post-frame 回调就会
//    fire-and-forget 一次 `HiveBoxes.meta.delete`（清除标记）。那是真实
//    异步，在 fake clock 下永不完成 —— 用例会挂到 30 秒超时，且**没有**
//    任何异常输出（纯挂起，最容易误判成「测试写得不对」）。`runAsync`
//    让这段时间走真实事件循环，写盘得以完成。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/features/profile/profile_page.dart';
import 'package:poemath/features/profile/providers/hive_key_recovery_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

const String _title = '部分本地记录暂时无法读取';

/// 同步读回标记（`box.get` 不 await，不受 fake clock 影响）。
Object? _marker() => HiveBoxes.meta.get(HiveKeys.metaHiveKeyRecovered);

/// 渲染「我的」页并把入场动画跑到静止。约束见文件头 ①、②。
///
/// **只用于「标记缺失/脏值」这类提示不会出现、因而不触发清除写盘的用例。**
/// 标记为 true 的用例必须自己把整段包进 `tester.runAsync` —— 提示一渲染就
/// 会 fire-and-forget 一次 `HiveBoxes.meta.delete`，那是真实异步，在 fake
/// clock 下永不完成，会把用例挂到 30 秒超时（见文件头 ③）。
Future<void> _pumpProfilePage(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [staticDayKeyOverride()],
      child: const MaterialApp(
        home: ProfilePage(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  // ── 纯逻辑：标记的读、清、幂等 ──────────────────────────────────────
  //
  // 这一组不打 widget，因此不受 fake clock 与动画影响，是清除语义的
  // 权威断言。
  group('标记读取与清除（纯逻辑）', () {
    test('markHiveKeyRecoveryShown 清掉标记', () async {
      await HiveBoxes.meta.put(HiveKeys.metaHiveKeyRecovered, true);
      expect(_marker(), isTrue);

      await markHiveKeyRecoveryShown();

      expect(_marker(), isNull);
    });

    test('markHiveKeyRecoveryShown 幂等，标记已不存在时也安静通过', () async {
      await markHiveKeyRecoveryShown();
      // 第二次（标记已不存在）不能抛 —— 它在 widget 的 post-frame 回调里，
      // 抛出去会变成未捕获异步异常。
      await markHiveKeyRecoveryShown();

      expect(_marker(), isNull);
    });

    test('标记为 true 时 provider 返回 true', () async {
      await HiveBoxes.meta.put(HiveKeys.metaHiveKeyRecovered, true);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(hiveKeyRecoveredProvider), isTrue);
    });

    test('标记缺失时为 false（正常启动与全新安装）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(hiveKeyRecoveredProvider), isFalse);
    });

    test('标记为非 true 的脏值时为 false', () async {
      // 备份导入/异常写入可能留下别的值；只有 true 才代表「刚刚发生降级」。
      await HiveBoxes.meta.put(HiveKeys.metaHiveKeyRecovered, 'yes');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(hiveKeyRecoveredProvider), isFalse);
    });
  });

  // ── 渲染事实：提示必须真的出现在页面上 ──────────────────────────────
  //
  // 上面那组证明「标记 → provider 为 true」，这组证明「provider 为 true
  // → 用户**看得见**」。少了这组，把 `ProfilePage` 里的 if 分支删掉也全绿。
  group('提示渲染', () {
    testWidgets('标记为 true 时「我的」页显示提示卡', (tester) async {
      // 整段包在 `runAsync` 里：提示渲染后会 fire-and-forget 一次
      // `HiveBoxes.meta.delete`（清除标记），那是**真实异步**。在 fake
      // clock 下它永不完成，用例会挂到 30 秒超时。`runAsync` 让这段时间
      // 走真实事件循环，delete 能正常落盘。
      await tester.runAsync(() async {
        await HiveBoxes.meta.put(HiveKeys.metaHiveKeyRecovered, true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [staticDayKeyOverride()],
            child: const MaterialApp(home: ProfilePage()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text(_title), findsOneWidget);
        // 文案必须给出原因与出路，不能只丢一句「出错了」。
        expect(find.textContaining('原始文件已隔离保留'), findsOneWidget);
        expect(find.textContaining('备份与恢复'), findsOneWidget);
      });
    });

    testWidgets('标记缺失时不显示提示（正常启动与全新安装）', (tester) async {
      await _pumpProfilePage(tester);

      expect(find.text(_title), findsNothing);
    });

    testWidgets('标记为非 true 的脏值时不显示提示', (tester) async {
      await tester.runAsync(
        () => HiveBoxes.meta.put(HiveKeys.metaHiveKeyRecovered, 'yes'),
      );

      await _pumpProfilePage(tester);

      expect(find.text(_title), findsNothing);
    });
  });
}
