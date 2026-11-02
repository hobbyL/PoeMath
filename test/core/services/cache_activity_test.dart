import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/cache_activity.dart';

void main() {
  test('有活动租约时拒绝清理，失败的生产者也会释放租约', () async {
    final started = Completer<void>();
    final complete = Completer<void>();
    final producer = CacheActivity.use(TemporaryCacheKind.updates, () async {
      started.complete();
      await complete.future;
      throw StateError('下载失败');
    });
    final failedProducer = expectLater(producer, throwsStateError);
    await started.future;
    var cleared = false;
    await expectLater(
      CacheActivity.clear(
        TemporaryCacheKind.updates,
        () async => cleared = true,
      ),
      throwsA(isA<CacheInUseException>()),
    );
    expect(cleared, isFalse);
    complete.complete();
    await failedProducer;
    await CacheActivity.clear(
      TemporaryCacheKind.updates,
      () async => cleared = true,
    );
    expect(cleared, isTrue);
  });

  test('清理期间新操作等待，清理失败后等待者仍正常启动', () async {
    final started = Completer<void>();
    final complete = Completer<void>();
    final events = <String>[];
    final clearing = CacheActivity.clear(TemporaryCacheKind.pickers, () async {
      events.add('清理开始');
      started.complete();
      await complete.future;
      events.add('清理结束');
      throw StateError('删除失败');
    });
    final failedClear = expectLater(clearing, throwsStateError);
    await started.future;
    final producer = CacheActivity.use(TemporaryCacheKind.pickers, () async {
      events.add('导入开始');
      return '导入完成';
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['清理开始']);
    complete.complete();
    await failedClear;
    expect(await producer, '导入完成');
    expect(events, ['清理开始', '清理结束', '导入开始']);
  });
}
