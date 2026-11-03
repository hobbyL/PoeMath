import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/credential_configuration_access.dart';

void main() {
  test('空闲凭据队列不依赖已经结束的调用 Zone', () async {
    final callbacks = <void Function()>[];
    final isolated = Zone.current.fork(
      specification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, callback) {
          callbacks.add(() => zone.runGuarded(callback));
        },
      ),
    );
    var firstFinished = false;
    isolated.run(() {
      CredentialConfigurationAccess.exclusive(() async => 'first').then((_) {
        firstFinished = true;
      });
    });
    while (callbacks.isNotEmpty) {
      callbacks.removeAt(0)();
    }
    expect(firstFinished, isTrue);

    // The isolated Zone is now retired: no further callbacks are pumped.
    expect(
      await CredentialConfigurationAccess.exclusive(() async => 'next')
          .timeout(const Duration(seconds: 1)),
      'next',
    );
    expect(callbacks, isEmpty);
  });

  test('失败释放排队请求，嵌套访问保持同一凭据事务', () async {
    final gate = Completer<void>();
    final order = <String>[];
    final first = CredentialConfigurationAccess.exclusive<void>(() async {
      order.add('first');
      await CredentialConfigurationAccess.exclusive(() async {
        order.add('nested');
      });
      await gate.future;
      throw StateError('synthetic failure');
    });
    final failed = expectLater(first, throwsStateError);
    final second = CredentialConfigurationAccess.exclusive(() async {
      order.add('second');
      return 2;
    });
    await Future<void>.delayed(Duration.zero);
    expect(order, ['first', 'nested']);
    gate.complete();
    await failed;
    expect(await second, 2);
    expect(order, ['first', 'nested', 'second']);
  });
}
