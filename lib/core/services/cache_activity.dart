import 'dart:async';

/// 有在途读写的临时文件不能被存储管理删除。
enum TemporaryCacheKind { updates, pickers, sharing, systemTts }

class CacheInUseException implements Exception {
  const CacheInUseException();

  @override
  String toString() => '缓存正在使用，请在操作完成后重试';
}

/// 按临时文件的实际生产者共享租约；清理期间新操作等待，不争用文件。
class CacheActivity {
  CacheActivity._();

  static final _users = <TemporaryCacheKind, int>{};
  static final _clearing = <TemporaryCacheKind, Completer<void>>{};

  static Future<T> use<T>(
    TemporaryCacheKind kind,
    Future<T> Function() action,
  ) async {
    while (_clearing.containsKey(kind)) {
      await _clearing[kind]!.future;
    }
    _users.update(kind, (count) => count + 1, ifAbsent: () => 1);
    try {
      return await action();
    } finally {
      final count = _users[kind]! - 1;
      if (count == 0) {
        _users.remove(kind);
      } else {
        _users[kind] = count;
      }
    }
  }

  static Future<T> clear<T>(
    TemporaryCacheKind kind,
    Future<T> Function() action,
  ) async {
    if ((_users[kind] ?? 0) > 0 || _clearing.containsKey(kind)) {
      throw const CacheInUseException();
    }
    final pending = Completer<void>();
    _clearing[kind] = pending;
    try {
      return await action();
    } finally {
      _clearing.remove(kind);
      pending.complete();
    }
  }
}
