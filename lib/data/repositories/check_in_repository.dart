// lib/data/repositories/check_in_repository.dart
//
// 层级：data/repositories
// 职责：每日打卡仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/repositories/activity_settlement_ledger.dart';

class CheckInRepository {
  /// 日期格式化辅助
  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 获取指定日期的打卡记录
  CheckIn? getByDate(DateTime date) {
    return HiveBoxes.checkIns.get(ProfileScope.key(_dateKey(date)));
  }

  /// 获取今日打卡记录
  CheckIn? getToday() => getByDate(DateTime.now());

  /// 记录今日打卡（创建或更新）
  Future<CheckIn> checkInToday() => ActivitySettlementLedger.serial(
          ActivitySettlementLedger.dailySummaryChannel, () async {
        final record = await _getOrCreateToday(isCheckedIn: true);
        if (!record.isCheckedIn) {
          final next = record.copy()..isCheckedIn = true;
          await HiveBoxes.checkIns.put(ProfileScope.key(next.date), next);
          return next;
        }
        return record;
      });

  Future<CheckIn> _getOrCreateToday({required bool isCheckedIn}) async {
    final now = DateTime.now();
    final dateStr = _dateKey(now);
    final key = ProfileScope.key(dateStr);

    var record = HiveBoxes.checkIns.get(key);
    if (record == null) {
      record = CheckIn(
        profileId: ProfileScope.currentId,
        date: dateStr,
        isCheckedIn: isCheckedIn,
      );
      await HiveBoxes.checkIns.put(key, record);
    }
    return record;
  }

  /// 更新今日数据
  Future<void> updateToday({
    String? activityId,
    int? addPoems,
    int? addMathTotal,
    int? addMathCorrect,
    int? addStars,
    int? addDuration,
  }) async {
    await updateForDate(
      DateTime.now(),
      activityId: activityId,
      addPoems: addPoems,
      addMathTotal: addMathTotal,
      addMathCorrect: addMathCorrect,
      addStars: addStars,
      addDuration: addDuration,
    );
  }

  Future<void> updateForDate(
    DateTime date, {
    String? activityId,
    int? addPoems,
    int? addMathTotal,
    int? addMathCorrect,
    int? addStars,
    int? addDuration,
  }) async {
    final dateStr = _dateKey(date);
    final key = ProfileScope.key(dateStr);
    Future<void> update() async {
      final record = HiveBoxes.checkIns.get(key)?.copy() ??
          CheckIn(
            profileId: ProfileScope.currentId,
            date: dateStr,
            isCheckedIn: false,
          );
      if (addPoems != null) {
        record.poemCount += addPoems;
        record.activitySources |= CheckIn.poemActivitySource;
      }
      if (addMathTotal != null) {
        record.mathTotalCount += addMathTotal;
        record.activitySources |= CheckIn.mathActivitySource;
      }
      if (addMathCorrect != null) record.mathCorrectCount += addMathCorrect;
      if (addStars != null) record.starsEarned += addStars;
      if (addDuration != null) record.durationSeconds += addDuration;
      if (activityId != null) {
        record.appliedActivityIds = [...record.appliedActivityIds, activityId];
      }
      await HiveBoxes.checkIns.put(key, record);
    }

    if (activityId == null) {
      await ActivitySettlementLedger.serial(
          ActivitySettlementLedger.dailySummaryChannel, update,);
      return;
    }
    await ActivitySettlementLedger.runOnce(
      channel: ActivitySettlementLedger.dailySummaryChannel,
      activityId: activityId,
      action: update,
      isApplied: () =>
          HiveBoxes.checkIns
              .get(key)
              ?.appliedActivityIds
              .contains(activityId) ??
          false,
    );
  }

  /// 判断今日是否已打卡
  bool isCheckedInToday() => getToday()?.isCheckedIn ?? false;

  /// 计算连续打卡天数（往回数）
  int calculateStreak() {
    int streak = 0;
    var date = DateTime.now();

    // 今天没打卡的话，从昨天开始数
    if (getByDate(date)?.isCheckedIn != true) {
      date = date.subtract(const Duration(days: 1));
    }

    while (getByDate(date)?.isCheckedIn == true) {
      streak++;
      date = date.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 获取某月的打卡记录（用于日历显示）
  List<CheckIn> getByMonth(int year, int month) {
    return HiveBoxes.checkIns.values.where((c) {
      if (c.profileId != ProfileScope.currentId) return false;
      final parts = c.date.split('-');
      if (parts.length != 3) return false;
      return int.parse(parts[0]) == year && int.parse(parts[1]) == month;
    }).toList();
  }

  /// 当月打卡天数
  int getMonthlyCount(int year, int month) {
    return getByMonth(year, month).where((c) => c.isCheckedIn).length;
  }
}
