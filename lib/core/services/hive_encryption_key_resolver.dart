// lib/core/services/hive_encryption_key_resolver.dart
//
// 层级：core/services
// 职责：启动时决定「用哪把 cipher 开 Hive」，并处理密钥丢失的降级。
//
// 暂时不可访问/写入失败保留文件并暴露重试；不可读文件隔离留底，不自动删除。

import 'dart:io';

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

  /// 部分文件无法读取，已隔离留底，其余数据继续使用。
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

  /// Every existing box is checked on every startup, including interrupted migrations.
  static Future<ResolvedCipher> resolve({
    required String boxDir,
    SecureCredentialStore? credentialStore,
  }) async {
    final provider = HiveEncryptionKeyProvider(
      store: credentialStore ?? SecureCredentialStore(),
    );
    final existing = await provider.loadOrCreate();
    final hasFiles = allBoxNames.any(
      (name) =>
          File('$boxDir/$name.hive').existsSync() ||
          File('$boxDir/$name.hive${HiveEncryptionMigration.plaintextBackupSuffix}')
              .existsSync(),
    );
    if (!hasFiles) {
      return (
        cipher: HiveAesCipher(existing.key),
        status: existing.isNew ? HiveKeyStatus.newInstall : HiveKeyStatus.ok,
      );
    }
    final results = await HiveEncryptionMigration.run(
      boxNames: allBoxNames,
      key: existing.key,
      boxDir: boxDir,
    );
    if (results.values.contains(BoxMigrationOutcome.failed)) {
      throw HiveError('加密迁移暂未完成，原数据和留底已保留，请重试');
    }
    final unreadable = results.entries
        .where((entry) => entry.value == BoxMigrationOutcome.unreadable)
        .map((entry) => entry.key)
        .toList();
    if (unreadable.isNotEmpty) {
      // Preserve undecodable files in a private recovery directory before reuse.
      // Never delete them or overwrite a valid stored key on probe failures.
      final recovery =
          await Directory('$boxDir/hive_recovery').create(recursive: true);
      for (final name in unreadable) {
        final source = File('$boxDir/$name.hive');
        final id = DateTime.now().microsecondsSinceEpoch;
        await source.rename('${recovery.path}/${id}_$name.hive');
      }
      AppLogger.e('隔离保留 ${unreadable.length} 个不可读数据库，可从备份恢复', tag: _tag);
    }
    return (
      cipher: HiveAesCipher(existing.key),
      status:
          unreadable.isEmpty ? HiveKeyStatus.ok : HiveKeyStatus.recoveredEmpty,
    );
  }

  /// Compatibility with callers; failed migrations no longer launch plaintext.
  static bool isPlaintext(HiveCipher cipher) => false;
}
