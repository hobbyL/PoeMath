import 'dart:async';

/// 配置、凭据与备份恢复共用的访问队列；嵌套迁移可重入。
class CredentialConfigurationAccess {
  CredentialConfigurationAccess._();

  static Future<void> _tail = Future<void>.value();
  static final Object _zoneKey = Object();
  static Object? _owner;

  static Future<T> exclusive<T>(Future<T> Function() operation) {
    if (_owner != null && identical(Zone.current[_zoneKey], _owner)) {
      return operation();
    }
    final result = _tail.then((_) async {
      final owner = Object();
      _owner = owner;
      try {
        return await runZoned(operation, zoneValues: {_zoneKey: owner});
      } finally {
        _owner = null;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
