import 'dart:async';

/// 配置、凭据与备份恢复共用的访问队列；嵌套迁移可重入。
class CredentialConfigurationAccess {
  CredentialConfigurationAccess._();

  static Future<void>? _tail;
  static final Object _zoneKey = Object();
  static Object? _owner;

  static Future<T> exclusive<T>(Future<T> Function() operation) {
    if (_owner != null && identical(Zone.current[_zoneKey], _owner)) {
      return operation();
    }
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return (() async {
      try {
        if (previous != null) await previous;
        final owner = Object();
        _owner = owner;
        try {
          return await runZoned(operation, zoneValues: {_zoneKey: owner});
        } finally {
          _owner = null;
        }
      } finally {
        // An idle queue must not keep a completed future from a retired Zone.
        if (identical(_tail, done.future)) _tail = null;
        done.complete();
      }
    })();
  }
}
