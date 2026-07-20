import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/repositories/activity_settlement_ledger.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('同一活动同一通道只执行一次', () async {
    var calls = 0;

    final first = await ActivitySettlementLedger.runOnce(
      channel: ActivitySettlementLedger.userStatsChannel,
      activityId: 'activity-1',
      action: () async {
        calls++;
      },
    );
    final second = await ActivitySettlementLedger.runOnce(
      channel: ActivitySettlementLedger.userStatsChannel,
      activityId: 'activity-1',
      action: () async {
        calls++;
      },
    );

    expect(first, isTrue);
    expect(second, isFalse);
    expect(calls, 1);
  });

  test('统计与每日汇总通道独立结算', () async {
    var calls = 0;

    for (final channel in [
      ActivitySettlementLedger.userStatsChannel,
      ActivitySettlementLedger.dailySummaryChannel,
    ]) {
      await ActivitySettlementLedger.runOnce(
        channel: channel,
        activityId: 'activity-1',
        action: () async {
          calls++;
        },
      );
    }

    expect(calls, 2);
  });

  test('执行失败不写标记并允许后续重试', () async {
    var calls = 0;

    await expectLater(
      ActivitySettlementLedger.runOnce(
        channel: ActivitySettlementLedger.userStatsChannel,
        activityId: 'activity-1',
        action: () async {
          calls++;
          throw StateError('write failed');
        },
      ),
      throwsStateError,
    );

    final retried = await ActivitySettlementLedger.runOnce(
      channel: ActivitySettlementLedger.userStatsChannel,
      activityId: 'activity-1',
      action: () async {
        calls++;
      },
    );

    expect(retried, isTrue);
    expect(calls, 2);
  });

  test('拒绝空通道和空活动 ID', () async {
    await expectLater(
      ActivitySettlementLedger.runOnce(
        channel: '',
        activityId: 'activity-1',
        action: () async {},
      ),
      throwsArgumentError,
    );
    await expectLater(
      ActivitySettlementLedger.runOnce(
        channel: ActivitySettlementLedger.userStatsChannel,
        activityId: ' ',
        action: () async {},
      ),
      throwsArgumentError,
    );
  });
}
