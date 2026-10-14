// test/features/home/home_day_key_provider_test.dart
//
// R7（首页日相关 Provider 跨午夜失效）专项测试：
// - dayKeyProvider 初始值为今日 yyyy-MM-dd
// - dayKey 变化（跨天）后，依赖它的日相关 Provider 重新计算
// - 未失效时 Provider 缓存旧值（不因外部数据变化而自动重算）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

/// 不触碰 Hive 的假打卡仓储：返回值由测试驱动，
/// 用于观察 Provider 是否真的重新执行了计算。
class _FakeCheckInRepo extends CheckInRepository {
  bool checked = false;
  int streak = 0;
  CheckIn? today;

  @override
  bool isCheckedInToday() => checked;

  @override
  int calculateStreak() => streak;

  @override
  CheckIn? getToday() => today;
}

/// 生产实现 `_todayKey()` 的等价副本（同格式、同口径）。
///
/// 断言「provider 初始值 == 今日」需要按同一时钟取值；若两端分别调
/// `DateTime.now()`，跨午夜瞬间会得到不同日期。基准在一次测试内只取一次。
String todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

void main() {
  test('dayKeyProvider 初始值为今日 yyyy-MM-dd', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final key = container.read(dayKeyProvider);
    expect(key, todayKey());
    expect(key, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('dayKey 跨天变化后 isCheckedInProvider 重新计算', () {
    final fake = _FakeCheckInRepo();
    final container = ProviderContainer(
      overrides: [checkInRepoProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    // 初始：未打卡
    expect(container.read(isCheckedInProvider), isFalse);

    // 外部数据变化但未失效：Provider 仍缓存旧值（证明依赖 dayKey 而非轮询）
    fake.checked = true;
    expect(container.read(isCheckedInProvider), isFalse);

    // dayKey 跨天 → 依赖失效 → 重算
    container.read(dayKeyProvider.notifier).state = '2000-01-01';
    expect(container.read(isCheckedInProvider), isTrue);
  });

  test('dayKey 跨天变化后 streakProvider / todayCheckInProvider 重新计算', () {
    final fake = _FakeCheckInRepo();
    final container = ProviderContainer(
      overrides: [checkInRepoProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(container.read(streakProvider), 0);
    expect(container.read(todayCheckInProvider), isNull);

    fake.streak = 7;
    fake.today = CheckIn(profileId: 'default', date: todayKey());

    // 未失效：缓存旧值
    expect(container.read(streakProvider), 0);
    expect(container.read(todayCheckInProvider), isNull);

    // 跨天失效：重算
    container.read(dayKeyProvider.notifier).state = '2000-01-01';
    expect(container.read(streakProvider), 7);
    expect(container.read(todayCheckInProvider), isNotNull);
  });

  testWidgets('dayKeyProvider dispose 时释放 Timer（无遗留 pending timer）',
      (tester) async {
    // 零断言回归：本用例原先是 `test(...)` + 注释「dispose 后无 pending
    // timer 抛错即通过」—— 但纯 `test()` **不检查** pending timer，
    // 所以 DayKeyNotifier 漏掉 `_timer?.cancel()` 时它依然全绿，
    // 而那个 30s 周期 Timer 会在真机上一直跑。
    //
    // 换成 `testWidgets` 后跑在 FakeAsync 下，flutter_test 会在用例结束时
    // 断言没有遗留 timer（"A Timer is still pending..."），注释里声称的
    // 检查才真正存在。下面再显式推时间，确认 Timer 不会在 dispose 后回调。
    final container = ProviderContainer();
    container.read(dayKeyProvider); // 触发 Timer 创建
    container.dispose();

    // 远超 30s 轮询周期：若 Timer 未取消，这里会触发已 dispose 容器的回调。
    await tester.pump(const Duration(minutes: 5));
  });
}
