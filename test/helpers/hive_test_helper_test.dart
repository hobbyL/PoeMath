import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/user_stats.dart';

import 'hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  testWidgets('无待写入时刷盘立即完成，不耗尽五秒兜底', (tester) async {
    final elapsed = Stopwatch()..start();
    await drainHiveWritesForTesting(tester);
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
  });

  testWidgets('跨 Box 的 fake zone 写入均完成，持续动画不阻塞刷盘', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CircularProgressIndicator()),
    );
    var written = false;
    unawaited(
      Future.wait([
        HiveBoxes.meta.put('drain-test', 1),
        HiveBoxes.settings.put('drain-test', 2),
        HiveBoxes.userStats.put(
          'drain-test',
          UserStats(profileId: 'default', totalStars: 3),
        ),
      ]).then((_) => written = true),
    );

    await drainHiveWritesForTesting(tester);

    expect(written, isTrue);
    expect(HiveBoxes.meta.get('drain-test'), 1);
    expect(HiveBoxes.settings.get('drain-test'), 2);
    expect(HiveBoxes.userStats.get('drain-test')!.totalStars, 3);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
