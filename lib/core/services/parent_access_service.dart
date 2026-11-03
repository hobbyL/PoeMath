import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

class ParentAccessDenied implements Exception {
  const ParentAccessDenied();
  @override
  String toString() => '请先由家长解锁';
}

/// PIN 与一次性恢复码仅保存加盐摘要，设备绑定，不参与任何备份。
class ParentAccessService extends ChangeNotifier with WidgetsBindingObserver {
  ParentAccessService({
    SecureCredentialStore? store,
    DateTime Function()? clock,
  })  : _store = store ?? SecureCredentialStore(),
        _clock = clock ?? DateTime.now;
  static final instance = ParentAccessService();
  static const unlockDuration = Duration(minutes: 5);
  final SecureCredentialStore _store;
  final DateTime Function() _clock;
  DateTime? _until;
  Timer? _expiry;
  bool _observing = false;
  bool _foreground = true;
  Future<void>? _operation;
  int _lockGeneration = 0;
  Object? _storageError;

  bool get enabled =>
      Hive.isBoxOpen('settings') &&
      HiveBoxes.settings
              .get('parent_protection_enabled', defaultValue: false) ==
          true;
  bool get isUnlocked =>
      _storageError == null &&
      _foreground &&
      enabled &&
      (_until?.isAfter(_clock()) ?? false);

  /// 首次建立 PIN 的资格不授予设置、额度或数据管理权限。
  bool get canSetPin =>
      _storageError == null &&
      _foreground &&
      Hive.isBoxOpen('settings') &&
      (!enabled || isUnlocked);
  bool get hasStorageError => _storageError != null;
  bool get needsResetNotice =>
      Hive.isBoxOpen('settings') &&
      HiveBoxes.settings
              .get('parent_protection_reset_notice', defaultValue: false) ==
          true;

  /// 系统可迁移 Hive，却不能迁移设备安全摘要。真实缺项时重设保护；
  /// 读取异常时保持锁定，绝不把异常当成新设备放行。
  Future<void> initialize() => _serial(() async {
        try {
          final raw = await _readRecord();
          if (enabled && raw == null) {
            await HiveBoxes.settings
                .put('parent_protection_reset_notice', true);
            await HiveBoxes.settings.put('parent_protection_enabled', false);
            lock();
          }
          _storageError = null;
          notifyListeners();
        } on Object catch (error) {
          _storageError = error;
          lock();
          rethrow;
        }
      });
  void assertAllowed() {
    if (!isUnlocked) throw const ParentAccessDenied();
  }

  void _assertCanSetPin() {
    if (!canSetPin) throw const ParentAccessDenied();
  }

  static Map<String, dynamic> _decodeRecord(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    for (final field in ['salt', 'recoverySalt', 'digest', 'recoveryDigest']) {
      final bytes = base64Decode(data[field] as String);
      final expectedLength =
          field.endsWith('Salt') || field == 'salt' ? 16 : 32;
      if (bytes.length != expectedLength) {
        throw const FormatException('家长验证记录不完整，请稍后重试');
      }
    }
    final failures = data['failures'];
    if (failures != null && (failures is! int || failures < 0)) {
      throw const FormatException('家长验证记录不完整，请稍后重试');
    }
    final blocked = data['blockedUntil'];
    if (blocked != null &&
        (blocked is! String || DateTime.tryParse(blocked) == null)) {
      throw const FormatException('家长验证记录不完整，请稍后重试');
    }
    return data;
  }

  Future<String?> _readRecord() async {
    try {
      final raw = await _store.readParentProtection();
      if (raw != null) _decodeRecord(raw);
      return raw;
    } on Object catch (error) {
      _storageError = error;
      lock();
      rethrow;
    }
  }

  Future<void> _saveAuthenticationRecord(Map<String, dynamic> data) async {
    try {
      await _store.saveParentProtection(jsonEncode(data));
    } on Object catch (error) {
      _storageError = error;
      lock();
      rethrow;
    }
  }

  void observeLifecycle() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!_foreground) lock();
  }

  void lock() {
    _lockGeneration++;
    _until = null;
    _expiry?.cancel();
    notifyListeners();
  }

  void _unlock() {
    if (!_foreground ||
        (_observing &&
            WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    _until = _clock().add(unlockDuration);
    _expiry?.cancel();
    _expiry = Timer(unlockDuration, lock);
    notifyListeners();
  }

  static bool validPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);
  static String _salt() =>
      base64Encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
  static Future<String> _digest(String secret, String salt) async {
    final key =
        await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 120000, bits: 256)
            .deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: base64Decode(salt),
    );
    return base64Encode(await key.extractBytes());
  }

  static bool _same(String left, String right) {
    var difference = left.length ^ right.length;
    for (var i = 0; i < left.length && i < right.length; i++) {
      difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return difference == 0;
  }

  static String _normalizeRecovery(String text) =>
      text.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _operation;
    final done = Completer<void>();
    _operation = done.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      done.complete();
      if (identical(_operation, done.future)) _operation = null;
    }
  }

  bool _isOperationCurrent(int generation, bool Function()? isCurrent) =>
      generation == _lockGeneration &&
      _foreground &&
      (isCurrent?.call() ?? true);

  Future<String> configure(String pin, {bool Function()? isCurrent}) =>
      _serial(() async {
        _assertCanSetPin();
        final generation = _lockGeneration;
        if (!_isOperationCurrent(generation, isCurrent)) {
          throw const ParentAccessDenied();
        }
        if (!validPin(pin)) throw const FormatException('PIN 须为 6 位数字');
        final salt = _salt();
        final recoverySalt = _salt();
        final recovery =
            List<int>.generate(16, (_) => Random.secure().nextInt(256))
                .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                .join()
                .toUpperCase();
        final record = <String, dynamic>{
          'salt': salt,
          'digest': await _digest(pin, salt),
          'recoverySalt': recoverySalt,
          'recoveryDigest': await _digest(recovery, recoverySalt),
          'failures': 0,
        };
        // 哈希期间后台失效时不允许悄悄改 PIN。
        _assertCanSetPin();
        if (!_isOperationCurrent(generation, isCurrent)) {
          throw const ParentAccessDenied();
        }
        final wasEnabled = enabled;
        final oldRecord = await _readRecord();
        if (!_isOperationCurrent(generation, isCurrent)) {
          throw const ParentAccessDenied();
        }
        try {
          await _store.saveParentProtection(jsonEncode(record));
          if (!_isOperationCurrent(generation, isCurrent)) {
            throw const ParentAccessDenied();
          }
          await HiveBoxes.settings.put('parent_protection_enabled', true);
          if (!_isOperationCurrent(generation, isCurrent)) {
            throw const ParentAccessDenied();
          }
        } on Object catch (error, stackTrace) {
          // 两个存储分别补偿，不能留下开启标记却没有可用验证记录。
          Object? compensationError;
          try {
            if (oldRecord == null) {
              await _store.deleteParentProtection();
            } else {
              await _store.saveParentProtection(oldRecord);
            }
          } on Object catch (failure) {
            compensationError = failure;
          }
          try {
            await HiveBoxes.settings
                .put('parent_protection_enabled', wasEnabled);
          } on Object catch (failure) {
            compensationError ??= failure;
          }
          if (compensationError != null) {
            _storageError = compensationError;
            lock();
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        try {
          await HiveBoxes.settings.delete('parent_protection_reset_notice');
        } on Object catch (error) {
          AppLogger.e('家长保护迁移提示清理失败', tag: 'ParentAccess', error: error);
        }
        if (_isOperationCurrent(generation, isCurrent)) _unlock();
        return RegExp('.{1,4}')
            .allMatches(recovery)
            .map((m) => m.group(0))
            .join('-');
      });

  Future<bool> authenticate(
    String secret, {
    bool recovery = false,
    bool Function()? isCurrent,
  }) =>
      _serial(() async {
        if (!enabled || !_foreground || _storageError != null) return false;
        final generation = _lockGeneration;
        if (!_isOperationCurrent(generation, isCurrent)) return false;
        final raw = await _readRecord();
        if (raw == null) {
          final error = StateError('此设备缺少验证记录，请返回后重试以重设保护');
          _storageError = error;
          lock();
          throw error;
        }
        final data = _decodeRecord(raw);
        final blocked =
            DateTime.tryParse(data['blockedUntil'] as String? ?? '');
        if (blocked != null && blocked.isAfter(_clock())) {
          throw StateError('尝试次数过多，请稍后再试');
        }
        final salt = data[recovery ? 'recoverySalt' : 'salt'] as String;
        final actual =
            await _digest(recovery ? _normalizeRecovery(secret) : secret, salt);
        if (!_isOperationCurrent(generation, isCurrent)) return false;
        if (!_same(
          actual,
          data[recovery ? 'recoveryDigest' : 'digest'] as String,
        )) {
          final failures = (data['failures'] as int? ?? 0) + 1;
          data['failures'] = failures;
          if (failures >= 5) {
            data['blockedUntil'] =
                _clock().add(const Duration(seconds: 30)).toIso8601String();
          }
          await _saveAuthenticationRecord(data);
          return false;
        }
        if (recovery) {
          // 恢复码只允许重设 PIN，不能解锁未配置的管理区。
          await HiveBoxes.settings.put('parent_protection_enabled', false);
          try {
            await _store.deleteParentProtection();
          } on Object catch (error, stackTrace) {
            AppLogger.e(
              '保护已关闭，旧验证摘要清理失败',
              tag: 'ParentAccess',
              error: error,
              stackTrace: stackTrace,
            );
          }
        } else {
          data['failures'] = 0;
          data.remove('blockedUntil');
          await _saveAuthenticationRecord(data);
        }
        if (!_isOperationCurrent(generation, isCurrent)) return false;
        if (recovery) {
          lock();
          return true;
        }
        _unlock();
        return isUnlocked;
      });

  Future<void> disable() => _serial(() async {
        assertAllowed();
        await HiveBoxes.settings.put('parent_protection_enabled', false);
        try {
          await _store.deleteParentProtection();
        } on Object catch (error, stackTrace) {
          AppLogger.e(
            '保护已关闭，旧验证摘要清理失败',
            tag: 'ParentAccess',
            error: error,
            stackTrace: stackTrace,
          );
        }
        lock();
      });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      lock();
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
