// lib/data/repositories/activity_settlement_ledger.dart
//
// 活动结算幂等账本。标记存入 meta box，并在同一进程内串行化相同活动。

import 'dart:async';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

class ActivitySettlementLedger {
  const ActivitySettlementLedger._();

  static const userStatsChannel = 'user_stats';
  static const dailySummaryChannel = 'daily_summary';

  static final Map<String, Future<void>> _inFlight = {};

  static Future<bool> runOnce({
    required String channel,
    required String activityId,
    required Future<void> Function() action,
  }) async {
    if (channel.trim().isEmpty) {
      throw ArgumentError.value(channel, 'channel', '不能为空');
    }
    if (activityId.trim().isEmpty) {
      throw ArgumentError.value(activityId, 'activityId', '不能为空');
    }

    final key = ProfileScope.key('activity_settlement:$channel:$activityId');

    while (true) {
      final pending = _inFlight[key];
      if (pending != null) {
        await pending;
        continue;
      }
      if (HiveBoxes.meta.get(key) == true) return false;

      final completer = Completer<void>();
      _inFlight[key] = completer.future;
      try {
        // 在当前 isolate 设置锁后再次检查，兼容外部刚写入的标记。
        if (HiveBoxes.meta.get(key) == true) return false;
        await action();
        await HiveBoxes.meta.put(key, true);
        return true;
      } finally {
        _inFlight.remove(key);
        completer.complete();
      }
    }
  }
}
