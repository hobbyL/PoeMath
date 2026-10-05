// test/helpers/day_key_override.dart
//
// 测试用静态 dayKey override：
// DayKeyNotifier.build 会启动 30s 轮询 Timer（前台跨午夜失效），
// pump 整个 App（含 HomePage）的 testWidgets 若用外部 container
// （UncontrolledProviderScope + addTearDown dispose），Timer 会在
// testWidgets 的 pending timer 检查时仍存活导致失败。
// 这些测试对「日 key」无跨天诉求，统一 override 为静态值跳过 Timer。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

/// 不启动轮询 Timer 的静态 DayKeyNotifier。
class StaticDayKeyNotifier extends DayKeyNotifier {
  StaticDayKeyNotifier([this.key = '2026-10-05']);

  final String key;

  @override
  String build() => key;
}

/// 供 ProviderScope/ProviderContainer overrides 使用的静态日 key override。
Override staticDayKeyOverride([String key = '2026-10-05']) =>
    dayKeyProvider.overrideWith(() => StaticDayKeyNotifier(key));
