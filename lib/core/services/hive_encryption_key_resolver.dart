// lib/core/services/hive_encryption_key_resolver.dart
//
// 层级：core/services
// 职责：启动时决定「用哪把 cipher 开 Hive」，并处理密钥丢失的降级。
//
// **本类的第一约束是「绝不抛异常」**：它在 AppBootstrap 的启动路径上，
// 抛出去会被包成永久重试页，用户连界面都进不去，比数据丢失更糟
// （design.md §7.4 / P6）。

import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/services/hive_encryption_key_provider.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/migrations/hive_encryption_migration.dart';

/// 本次启动的密钥状态，决定要不要给用户看提示。
enum HiveKeyStatus {
  /// 正常：密钥可用，数据以密文读写。
  ok,

  /// 密钥丢失/损坏，已用新密钥重建空数据。
  /// **必须提示用户** —— 他会看到学习记录不见了，静默重建是数据丢失事故的伪装。
  recoveredEmpty,

  /// 全新安装：生成密钥、建空 box，无需提示。
  newInstall,
}

/// 启动时应使用的 cipher 与状态。
typedef ResolvedCipher = ({HiveCipher cipher, HiveKeyStatus status});

class HiveEncryptionKeyResolver {
  const HiveEncryptionKeyResolver._();

  static const String _tag = 'HiveEncryption';

  /// 全部 box 名。加密迁移必须覆盖**每一个**，漏掉一个就是一处明文泄漏。
  static const List<String> allBoxNames = [
    HiveKeys.poemBox,
    HiveKeys.authorBox,
    HiveKeys.formulaBox,
    HiveKeys.progressBox,
    HiveKeys.poemFavoriteBox,
    HiveKeys.reviewBox,
    HiveKeys.mistakeBox,
    HiveKeys.mathSessionBox,
    HiveKeys.formulaFavoriteBox,
    HiveKeys.achievementBox,
    HiveKeys.checkInBox,
    HiveKeys.userStatsBox,
    HiveKeys.challengeRecordBox,
    HiveKeys.learningActivityBox,
    HiveKeys.llmProblemBox,
    HiveKeys.conversationBox,
    HiveKeys.messageBox,
    HiveKeys.settingsBox,
    HiveKeys.metaBox,
  ];

  /// 判定顺序（design.md §7.3）：
  ///
  /// 1. 密钥存在 → 试着用它开 box。
  ///    - 成功：`ok`。
  ///    - 失败：密钥损坏或与现存数据不匹配 → 走降级。
  /// 2. 密钥不存在 + 有明文 box → 生成密钥 + 迁移 → `ok`。
  /// 3. 密钥不存在 + 无文件 → 全新安装，生成密钥 → `newInstall`。
  ///
  /// [boxDir] 为 Hive 数据目录；默认取 `Hive.initFlutter()` 定位的那个，
  /// 测试可显式传入。
  static Future<ResolvedCipher> resolve({
    required String boxDir,
    SecureCredentialStore? credentialStore,
  }) async {
    final provider = HiveEncryptionKeyProvider(
      store: credentialStore ?? SecureCredentialStore(),
    );

    final hasAnyFile = _anyBoxFileExists(boxDir);

    final existing = await provider.loadOrCreate();

    if (!existing.isNew) {
      // 有密钥：验证它能否打开现存数据。
      final usable = await _canOpenAnyExisting(
        boxNames: allBoxNames,
        key: existing.key,
        boxDir: boxDir,
      );
      if (usable) {
        return (cipher: HiveAesCipher(existing.key), status: HiveKeyStatus.ok);
      }
      // 有密钥但打不开任何现存 box → 密钥与数据不匹配（换机恢复备份、
      // 设备安全存储被清、密钥被覆盖）。按密钥丢失降级。
      return _recoverEmpty(provider: provider, boxDir: boxDir);
    }

    // 本次新生成密钥。此时要区分「全新安装」与「有明文数据待迁移」——
    // 前者无事发生，后者需要把明文转密文，否则新密钥打不开旧明文 box。
    if (!hasAnyFile) {
      return (
        cipher: HiveAesCipher(existing.key),
        status: HiveKeyStatus.newInstall,
      );
    }

    return _migratePlaintext(
      provider: provider,
      key: existing.key,
      boxDir: boxDir,
    );
  }

  /// 把明文 box 迁移到密文。
  ///
  /// 迁移失败**不抛异常**：退回明文继续用（此时数据仍可读，只是还没加密），
  /// 下次启动重试。这比让用户开不了 App 好得多。
  static Future<ResolvedCipher> _migratePlaintext({
    required HiveEncryptionKeyProvider provider,
    required List<int> key,
    required String boxDir,
  }) async {
    try {
      await HiveEncryptionMigration.run(
        boxNames: allBoxNames,
        key: key,
        boxDir: boxDir,
      );
      return (cipher: HiveAesCipher(key), status: HiveKeyStatus.ok);
    } on Object catch (error, stack) {
      // 迁移失败：删掉刚生成但没派上用场的密钥，租明文模式继续启动。
      // 不删的话下次启动会「有密钥」，而去开明文 box 会失败，
      // 被误判成密钥损坏 → 降级清空数据 —— 那才是真正的事故。
      AppLogger.e(
        'Hive 加密迁移失败，本次以明文模式继续（数据未加密，下次启动重试）',
        tag: _tag,
        error: error,
        stackTrace: stack,
      );
      try {
        await provider.deleteKey();
      } on Object catch (cleanupError) {
        AppLogger.e('清理迁移失败时生成的密钥未成功', tag: _tag, error: cleanupError);
      }
      return (cipher: _noCipher, status: HiveKeyStatus.ok);
    }
  }

  /// 建降级：放弃不可解密的数据，用新密钥空数据继续启动。
  static Future<ResolvedCipher> _recoverEmpty({
    required HiveEncryptionKeyProvider provider,
    required String boxDir,
  }) async {
    AppLogger.e(
      'Hive 加密密钥无法解开现有数据，按密钥丢失处理：'
      '删除不可读密文并重建空数据',
      tag: _tag,
    );

    // 删掉打不开的 .hive 文件。它们已是不可读密文，留着只占磁盘。
    // `.lock` 一并删，避免残留锁让新 box 打不开。
    var deleted = 0;
    for (final name in allBoxNames) {
      for (final suffix in ['.hive', '.lock']) {
        final f = File('$boxDir/$name$suffix');
        if (f.existsSync()) {
          try {
            await f.delete();
            deleted++;
          } on Object catch (error) {
            AppLogger.e('删除不可读 box 文件失败：${f.path}', tag: _tag, error: error);
          }
        }
      }
    }
    AppLogger.d('已删除 $deleted 个不可读文件', tag: _tag);

    final newKey = await provider.regenerate();
    return (
      cipher: HiveAesCipher(newKey),
      status: HiveKeyStatus.recoveredEmpty,
    );
  }

  /// 「不加密」的哨兵。
  ///
  /// Hive 的 `openBox` 接受 `encryptionCipher: null` 表示不加密，但
  /// [ResolvedCipher] 的 `cipher` 是非空类型，因此这里用一个显式哨兵表达
  /// 「本次以明文模式启动」——调用方（`HiveBoxes.init`）需要能区分它，
  /// 否则没法把 null 传下去。
  static final HiveCipher _noCipher = _PlaintextCipher();

  /// 判断是否以明文模式启动（迁移失败时的退路）。
  static bool isPlaintext(HiveCipher cipher) => cipher is _PlaintextCipher;
}

/// 表达「不加密」的哨兵 cipher。
///
/// 不实现任何真实加解密 —— 调用方见到它就传 `null` 给 `HiveBoxes.init`。
/// 若它被真正用于读写，说明调用点漏了 `isPlaintext` 判断，直接抛错暴露。
class _PlaintextCipher extends HiveCipher {
  /// 非 const：`HiveCipher` 的父类构造函数不是 const，子类无法声明 const 构造。
  _PlaintextCipher();

  @override
  int calculateKeyCrc() => throw UnsupportedError(_message);

  @override
  int maxEncryptedSize(Uint8List inp) => throw UnsupportedError(_message);

  @override
  int encrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) =>
      throw UnsupportedError(_message);

  @override
  int decrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) =>
      throw UnsupportedError(_message);

  static const String _message =
      '明文哨兵不应被用于读写；调用方漏判 HiveEncryptionKeyResolver.isPlaintext';
}

/// 该目录下是否已存在任一 box 文件。
bool _anyBoxFileExists(String boxDir) {
  for (final name in HiveEncryptionKeyResolver.allBoxNames) {
    if (File('$boxDir/$name.hive').existsSync()) return true;
  }
  return false;
}

/// 现存文件中**至少有一个**能用 [key] 打开。
///
/// 用「至少一个」而非「全部」：某个 box 文件损坏不应导致整体判定为
/// 密钥不匹配 —— 那会清空其他完好的 box。
///
/// 一个文件都不存在时返回 `true`（视为「密钥可用」）：没有数据要解，
/// 谈不上密钥不匹配。调用方只在已确认存在文件时才走到这里，这个分支是
/// 文件在检查与打开之间消失的兜底 —— 返回 `true` 保持现状，总好过
/// 误判成密钥丢失去删数据。
Future<bool> _canOpenAnyExisting({
  required List<String> boxNames,
  required List<int> key,
  required String boxDir,
}) async {
  var sawAnyFile = false;
  for (final name in boxNames) {
    if (!File('$boxDir/$name.hive').existsSync()) continue;
    sawAnyFile = true;
    if (await HiveEncryptionMigration.canOpenWithKey(name, key)) return true;
  }
  // 有文件但一个都打不开 → 密钥真的不匹配。
  // 没有文件 → 无数据可判，按可用处理。
  return !sawAnyFile;
}
