import 'dart:async';
import 'dart:convert';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

/// 本机草稿不随备份迁移，恢复学习数据成功后清除，避免重放旧结算。
class PracticeDraftRepository {
  PracticeDraftRepository()
    : _epoch =
          HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0) as int;

  final int _epoch;
  static bool _restoring = false;
  static final Object _restoreZone = Object();
  static final Object _writeZone = Object();
  static final Set<Future<void>> _active = {};
  static bool get isRestoring => _restoring;
  static void assertSnapshotAllowed() {
    if (_restoring && Zone.current[_restoreZone] != true) {
      throw StateError('正在恢复数据，请稍后创建快照');
    }
  }

  void assertCurrent() {
    if (_restoring && Zone.current[_writeZone] != true) {
      throw StateError('正在恢复学习数据，请稍后重新进入练习');
    }
    if (_epoch != HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0)) {
      throw StateError('学习数据已恢复，此练习已失效，请重新进入');
    }
  }

  /// 一次完整结算的跨 box 写入也必须登记，恢复会先排空这些写入。
  /// 页面在建立时捕获本实例，恢复后不能重新取实例继续提交旧结果。
  Future<T> guard<T>(Future<T> Function() action) async {
    assertCurrent();
    final done = Completer<void>();
    _active.add(done.future);
    try {
      final value = await runZoned(action, zoneValues: {_writeZone: true});
      assertCurrent();
      return value;
    } finally {
      _active.remove(done.future);
      done.complete();
    }
  }

  /// 恢复前阻止新练习写入，并排空已经进入仓储的写入。
  static Future<T> whileRestoring<T>(Future<T> Function() restore) async {
    if (Zone.current[_restoreZone] == true) return restore();
    if (_restoring) throw StateError('正在恢复学习数据');
    _restoring = true;
    try {
      await Future.wait(_active.toList());
      await Future.wait(
        _writes.values.map((work) => work.catchError((Object _) {})),
      );
      return await runZoned(restore, zoneValues: {_restoreZone: true});
    } finally {
      _restoring = false;
    }
  }

  static const kinds = ['math', 'word'];
  static const poemKinds = ['poemQuiz', 'poemRecite', 'poemDictation'];
  static const _prefix = 'practice_draft:';
  static final Map<String, Future<void>> _writes = {};
  static final Map<String, Object> _owners = {};
  final Map<String, Object> _leases = {};

  String _key(String kind, [String? scope]) {
    if (poemKinds.contains(kind)) {
      if (scope == null || scope.isEmpty) {
        throw ArgumentError.value(scope, 'scope');
      }
      return ProfileScope.key('$_prefix$kind:${Uri.encodeComponent(scope)}');
    }
    if (!kinds.contains(kind) || scope != null) {
      throw ArgumentError.value(kind, 'kind');
    }
    return ProfileScope.key('$_prefix$kind');
  }

  /// 同一作用域的新页面取得所有权后，旧页面的延迟保存不能覆盖它。
  void claim(String kind, {required String scope}) {
    assertCurrent();
    final key = _key(kind, scope);
    final lease = Object();
    _owners[key] = lease;
    _leases[key] = lease;
  }

  void assertOwner(String kind, {required String scope}) {
    assertCurrent();
    final key = _key(kind, scope);
    if (_leases[key] == null || _owners[key] != _leases[key]) {
      throw StateError('练习已切换，请重新进入');
    }
  }

  Iterable<String> scopes(String kind) {
    if (!poemKinds.contains(kind)) throw ArgumentError.value(kind, 'kind');
    final prefix = ProfileScope.key('$_prefix$kind:');
    return HiveBoxes.meta.keys
        .whereType<String>()
        .where((key) => key.startsWith(prefix))
        .map((key) => Uri.decodeComponent(key.substring(prefix.length)))
        .toList();
  }

  Map<String, dynamic>? get(String kind, {String? scope}) {
    final raw = HiveBoxes.meta.get(_key(kind, scope));
    if (raw == null) return null;
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    if ((data['epoch'] as int? ?? 0) !=
        HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0)) {
      return null;
    }
    if (data['v'] != 1 ||
        data['profileId'] != ProfileScope.currentId ||
        data['kind'] != kind ||
        data['scope'] != scope) {
      throw const FormatException('练习草稿版本或档案不匹配');
    }
    return data;
  }

  bool exists(String kind, {String? scope}) =>
      HiveBoxes.meta.containsKey(_key(kind, scope));

  Future<void> save(String kind, Map<String, dynamic> data, {String? scope}) {
    final key = _key(kind, scope);
    final profileId = ProfileScope.currentId;
    final revision = ProfileScope.revision;
    final lease = _leases[key];
    // 排队前编码，后续页面状态变化不能改变待写快照。
    final json = jsonEncode({
      ...data,
      'v': 1,
      'epoch': _epoch,
      'profileId': ProfileScope.currentId,
      'kind': kind,
      if (scope != null) 'scope': scope,
    });
    return _enqueue(key, () async {
      assertCurrent();
      if (scope != null &&
          (profileId != ProfileScope.currentId ||
              revision != ProfileScope.revision ||
              lease == null ||
              _owners[key] != lease)) {
        throw StateError('练习已切换，旧草稿不能覆盖当前练习');
      }
      await HiveBoxes.meta.put(key, json);
    });
  }

  Future<void> remove(String kind, {String? sessionId, String? scope}) {
    final key = _key(kind, scope);
    return _enqueue(key, () async {
      assertCurrent();
      if (sessionId != null &&
          get(kind, scope: scope)?['sessionId'] != sessionId) {
        return;
      }
      await HiveBoxes.meta.delete(key);
      if (scope != null) _owners.remove(key);
    });
  }

  static Future<void> _enqueue(String key, Future<void> Function() action) {
    final previous = _writes[key];
    final work = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          /* 后续检查点允许重试。 */
        }
      }
      await action();
    }();
    _writes[key] = work;
    return work.whenComplete(() {
      if (identical(_writes[key], work)) _writes.remove(key);
    });
  }

  static Future<void> clearAll({bool advanceEpoch = true}) async {
    if (advanceEpoch) {
      await HiveBoxes.meta.put(
        'practice_draft_epoch',
        (HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0) as int) +
            1,
      );
    }
    // 包括其他档案的草稿；备份会整体替换所有档案数据。
    final keys = HiveBoxes.meta.keys
        .whereType<String>()
        .where((key) => key.contains('_$_prefix'))
        .toList();
    for (final key in keys) {
      // durable epoch 已使旧草稿不可重放；删除失败只留下不可见的缓存，
      // 不把已成功替换的学习数据回滚成半套草稿状态。
      try {
        await _enqueue(key, () => HiveBoxes.meta.delete(key));
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          '恢复后草稿缓存清理失败，旧草稿已失效',
          tag: 'PracticeDraft',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Stream<void> changes() => HiveBoxes.meta
      .watch()
      .where(
        (event) =>
            event.key == 'practice_draft_epoch' ||
            event.key.toString().contains('_$_prefix'),
      )
      .map((_) {});
}
