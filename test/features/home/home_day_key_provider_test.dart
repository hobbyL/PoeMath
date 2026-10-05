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

  test('dayKeyProvider dispose 时释放 Timer（容器可正常关闭）', () {
    final container = ProviderContainer();
    container.read(dayKeyProvider); // 触发 Timer 创建
    container.dispose();
    // dispose 后无 pending timer 抛错即通过
  });
}
