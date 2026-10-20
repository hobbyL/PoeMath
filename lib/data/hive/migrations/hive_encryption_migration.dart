// 明文 Hive -> 密文：完整源文件 -> 持久备份 -> 临时密文 -> 重开验证 -> rename。
// 内存 backend 负责解绑 HiveObject；clear 不触碰源文件。
// 上次未提交的 .plaintext.bak 在下次启动优先恢复。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_value_snapshot.dart';

/// 单个 box 的迁移结果。
enum BoxMigrationOutcome {
  /// 已是密文（用新 key 能打开），无需处理。
  alreadyEncrypted,

  /// 明文 box 已成功转为密文。
  migrated,

  /// 文件不存在（全新安装或该 box 从未写过）。
  absent,

  /// 空文件（0 字节）。**无内容可泄漏，也无内容可迁移**，直接跳过。
  ///
  /// 单列一条而不是混进 `alreadyEncrypted`：0 字节文件用任意 cipher 都能
  /// 打开（没有 frame 可校验 checksum），把它记成「已加密」是错的说法，
  /// 排查磁盘加密状态时会把「确实是空的」误导成「已经处理过了」。
  empty,

  /// **既非本密钥密文、又非可读明文** —— 本次无法解码，调用方必须隔离留底。
  ///
  /// 典型来源：半迁移状态（进程被杀，留下用旧密钥加密的 box），或换机
  /// 恢复备份带来的异密钥密文。`run()` 会跳过它、继续迁移其余 box，
  /// 把结论留给调用方。
  unreadable,

  /// 可读数据的迁移写入失败，原文件/备份保留，启动必须重试。
  failed,
}

class HiveEncryptionMigration {
  const HiveEncryptionMigration._();

  static const String _tag = 'HiveEncryptionMigration';

  /// 明文备份文件的后缀。
  static const String plaintextBackupSuffix = '.plaintext.bak';

  /// 逐个迁移 [boxNames] 到 [key] 加密。
  ///
  /// [boxDir] 是 Hive 数据目录（`Hive.initFlutter()` 选定的那个）。
  /// 返回每个 box 的结果，供上层汇总日志。
  ///
  /// 分别报告不可读和写入失败；后者必须保留原状并让启动重试。
  static Future<Map<String, BoxMigrationOutcome>> run({
    required List<String> boxNames,
    required List<int> key,
    required String boxDir,
  }) async {
    final cipher = HiveAesCipher(key);

    // 先把 Hive 里已打开的 box 全部关掉。
    //
    // 必须做：`Hive.openBox(name)` 若发现同名 box 已打开，会**直接返回缓存
    // 实例并忽略传入的 encryptionCipher**（hive 的 `hive_impl.dart:76`）。
    // 于是「用 cipher 试开」这个检测动作会命中旧的明文实例、报告成功，
    // 迁移判断为「已加密」而跳过 —— 数据永远留在明文状态。
    // 关掉之后 openBox 才会真的按 cipher 去读磁盘。
    await Hive.close();
    Hive.init(boxDir);

    final results = <String, BoxMigrationOutcome>{};

    for (final name in boxNames) {
      try {
        results[name] = await _migrateBox(
          name: name,
          cipher: cipher,
          boxDir: boxDir,
        );
      } on Object catch (error, stack) {
        // 写入或验证失败不能当作密钥丢失；保留留底，启动重试。
        AppLogger.e(
          'box「$name」迁移未完成，保留文件等待重试',
          tag: _tag,
          error: error,
          stackTrace: stack,
        );
        results[name] = BoxMigrationOutcome.failed;
      }
    }

    final migrated = results.entries
        .where((e) => e.value == BoxMigrationOutcome.migrated)
        .map((e) => e.key)
        .toList();
    if (migrated.isNotEmpty) {
      AppLogger.d(
        'Hive 加密迁移完成，已转换 ${migrated.length} 个 box：'
        '${migrated.join(', ')}',
        tag: _tag,
      );
    }
    return results;
  }

  /// 判断单个 box 是否已经能用 [key] 打开。
  ///
  /// 用于「有密钥 + 有文件」时区分「已加密」与「明文」。
  ///
  /// **必须用 `crashRecovery: false`**：Hive 默认开启崩溃恢复，遇到
  /// checksum 不符时（错密钥、把明文当密文解）会打印 `Recovering corrupted
  /// box.`、**把文件截断到 0 字节**、然后成功返回一个空 box
  /// （见 hive 的 `storage_backend_vm.dart:93`）。那等于「检测」这个动作
  /// 本身把用户数据删了，而且返回值还告诉你一切正常。
  /// 关掉之后它改为抛 `HiveError('Wrong checksum...')`，这才是可用的判据。
  ///
  /// 另见 [_openProbe]：Hive 在打开失败时会把同一个错误上报两次，必须隔离。
  static Future<bool> canOpenWithKey(String name, List<int> key) =>
      _openProbe(name, HiveAesCipher(key));

  /// 判断 [name] 是否是**可读明文** box（即迁移真的能成功）。
  ///
  /// 用途：密钥不存在时，`HiveEncryptionKeyResolver` 需要区分
  /// 「有明文待迁移」与「有密文但密钥丢了」。**只看文件存在性不够** ——
  /// 两种情况都是「文件在、密钥不在」，但前者应迁移、后者应降级清空。
  /// 误判成前者会让迁移失败退回明文模式，而 `Hive.openBox` 的默认
  /// `crashRecovery` 会把解不开的密文**就地截断成空 box**，再被应用写进
  /// 新数据 —— 用户数据被静默销毁（真机实测过，见 research 文档场景 3）。
  ///
  /// 空文件（0 字节）返回 `true`：它没有内容可迁移，但也没有「解不开的
  /// 密文」风险，按明文处理是安全的（`_migrateBox` 会判为 `empty` 跳过）。
  ///
  /// 必须关 `crashRecovery`，理由同 [canOpenWithKey]；错误隔离见 [_openProbe]。
  static Future<bool> canOpenAsPlaintext(String name) =>
      // 探测前确保没有同名 box 处于打开状态：`openBox` 对已打开的 box
      // 会直接返回缓存实例并**忽略传入的 cipher**，那样探出来的结论是假的。
      // 调用方（resolver）此时尚未 init 任何 box，这里是防御性处理。
      Hive.isBoxOpen(name) ? Future.value(false) : _openProbe(name, null);

  /// 试着用 [cipher] 打开 [name]，成功返回 true。
  ///
  /// [cipher] 为 `null` 表示按**明文**打开（用于 [canOpenAsPlaintext]）。
  ///
  /// 关掉 `crashRecovery` 后 Hive 的**失败路径会把同一个错误上报两次**：
  /// `hive_impl.dart:118` 既 `completer.completeError(error)` 又 `rethrow`，
  /// 一份被下面的 `try` 捕获，另一份变成 unhandled zone error。后者会污染
  /// 全局错误处理（测试里直接判失败，release 里被 `PlatformDispatcher.onError`
  /// 记成「未捕获异常」），而它本就是我们预期内、已处理的情况。
  ///
  /// 因此把这次打开放进一个吞掉错误的 Zone。**注意两个细节**（都是实测出来的）：
  ///
  /// 1. 不能 `await runZonedGuarded(...)` 就完事：那份重复上报是**在 zone 体
  ///    结束后才异步送达**的，那时 zone 已销毁、错误会漏出去。
  /// 2. 所以用 `Completer` 让 zone 体自己报告完成，之后再显式等一小段时间
  ///    把迟到的错误排空 —— 这段时间里 zone 仍然存活并接住它。
  static Future<bool> _openProbe(String name, HiveCipher? cipher) =>
      _guarded(() async {
        final box = await Hive.openBox<dynamic>(
          name,
          encryptionCipher: cipher,
          crashRecovery: false,
        );
        await box.close();
      });

  /// 使用公共内存 backend 读取，clear 只解绑内存对象，不触碰源文件。
  static Future<Map<dynamic, dynamic>?> _openAndDump(
    String name,
    Uint8List bytes,
  ) async {
    Map<dynamic, dynamic>? dump;
    final ok = await _guarded(() async {
      final box = await Hive.openBox<dynamic>(
        '__migration_source_$name',
        bytes: bytes,
        crashRecovery: false,
      );
      try {
        dump = {for (final key in box.keys) key: box.get(key)};
        await box.clear();
      } finally {
        await box.close();
      }
    });
    return ok ? dump : null;
  }

  /// 在隔离 Zone 里执行 [body]，吞掉 Hive 重复上报的错误。
  ///
  /// **背景**：关掉 `crashRecovery` 后，Hive 的失败路径会把同一个错误上报
  /// **两次** —— `hive_impl.dart:118` 既 `completer.completeError(error)`
  /// 又 `rethrow`。一份被 `body` 的 try/catch 接住，另一份变成 unhandled
  /// zone error，污染全局错误处理（测试里直接判失败，release 里被
  /// `PlatformDispatcher.onError` 记成「未捕获异常」），而它本就是我们
  /// 预期内、已处理的情况。
  ///
  /// **两个实测出来的细节**：
  ///
  /// 1. 不能 `await runZonedGuarded(...)` 就完事：重复上报是在 zone 体结束
  ///    **之后**才异步送达的，那时 zone 已销毁、错误会漏出去。
  /// 2. 所以用 `Completer` 让 zone 体自己报告完成，之后再等一小段时间把
  ///    迟到的错误排空 —— 这期间 zone 仍存活并接住它。
  ///
  /// 返回 `body` 是否正常完成。
  static Future<bool> _guarded(
    Future<void> Function() body, {
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    var succeeded = false;
    final done = Completer<void>();

    runZonedGuarded(
      () {
        () async {
          try {
            await body();
            succeeded = true;
          } on Object catch (error, stack) {
            onError?.call(error, stack);
          } finally {
            if (!done.isCompleted) done.complete();
          }
        }();
      },
      // 故意吞掉：这是被重复上报的同一个错误。
      (_, __) {},
    );

    await done.future;
    // 排空迟到的重复上报。这条路径只在「打开失败」时走到，
    // 不影响正常启动耗时。
    if (!succeeded) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return succeeded;
  }

  static Future<BoxMigrationOutcome> _migrateBox({
    required String name,
    required HiveAesCipher cipher,
    required String boxDir,
  }) async {
    final file = File('$boxDir/$name.hive');
    final backup = File('${file.path}$plaintextBackupSuffix');
    // 留底尚未删除表示上次尚未提交。完整明文留底是恢复事实源。
    if (backup.existsSync()) {
      final bytes = await backup.readAsBytes();
      if (await _openAndDump(name, bytes) == null) {
        throw HiveError('迁移留底无法读取，原文件已保留：$name');
      }
      await file.writeAsBytes(bytes, flush: true);
      await backup.delete();
    }
    if (!file.existsSync()) return BoxMigrationOutcome.absent;
    if (await file.length() == 0) return BoxMigrationOutcome.empty;
    if (await _tryOpen(name, cipher)) {
      return BoxMigrationOutcome.alreadyEncrypted;
    }
    final original = await file.readAsBytes();
    final values = await _openAndDump(name, original);
    if (values == null) return BoxMigrationOutcome.unreadable;

    final expected = {
      for (final entry in values.entries)
        entry.key: HiveValueSnapshot.encode(entry.value),
    };

    // 原文件完整保留；备份失败时尚未发生任何破坏性写入。
    final pendingBackup = File('${backup.path}.pending');
    await pendingBackup.writeAsBytes(original, flush: true);
    await pendingBackup.rename(backup.path);
    final targetName = '__migration_target_$name';
    final target = File('$boxDir/$targetName.hive');
    try {
      // 中断留下的临时产物没有提交，重新生成，不读取其中的半写数据。
      if (target.existsSync()) await target.delete();
      Object? writeError;
      StackTrace? writeStack;
      final written = await _guarded(
        () async {
          final encrypted = await Hive.openBox<dynamic>(
            targetName,
            path: boxDir,
            encryptionCipher: cipher,
            crashRecovery: false,
          );
          try {
            if (values.isNotEmpty) await encrypted.putAll(values);
            await encrypted.flush();
            await encrypted.compact();
          } finally {
            await encrypted.close();
          }
          await _verify(targetName, cipher, expected, boxDir: boxDir);
        },
        onError: (error, stack) {
          writeError = error;
          writeStack = stack;
        },
      );
      if (!written) {
        Error.throwWithStackTrace(
          writeError ?? StateError('迁移写入失败'),
          writeStack ?? StackTrace.current,
        );
      }
      // 同目录 rename 切换；进程中断由上面的 backup 恢复路径收敛。
      await target.rename(file.path);
      await backup.delete();
      return BoxMigrationOutcome.migrated;
    } on Object {
      // 文件从未 clear；若切换已发生，恢复完整留底。失败仍保留 .bak。
      if (backup.existsSync()) {
        await file.writeAsBytes(await backup.readAsBytes(), flush: true);
      }
      rethrow;
    }
  }

  /// 同 key 重开并逐键核对。
  ///
  /// 只断言「键数一致」不够：值在密文往返里被写坏（编码错、截断）时
  /// 键数仍然对得上。这里比对实际值。
  static Future<void> _verify(
    String name,
    HiveAesCipher cipher,
    Map<dynamic, String> expected, {
    required String boxDir,
  }) async {
    final reopened = await Hive.openBox<dynamic>(
      name,
      path: boxDir,
      encryptionCipher: cipher,
      // 同样必须关：否则写坏的密文会被「恢复」成空 box，
      // 而空 box 的键数（0）与期望值一比就露馅，但错误信息会指向
      // 「键数不符」而非真正的「文件写坏了」。
      crashRecovery: false,
    );
    try {
      if (reopened.length != expected.length) {
        throw StateError(
          'box「$name」密文抽查键数不符：'
          '期望 ${expected.length}，实际 ${reopened.length}',
        );
      }
      for (final entry in expected.entries) {
        final actual = reopened.get(entry.key);
        if (!reopened.containsKey(entry.key) ||
            HiveValueSnapshot.encode(actual) != entry.value) {
          throw StateError(
            'box「$name」密文抽查值不符，key=${entry.key}',
          );
        }
      }
    } finally {
      await reopened.close();
    }
  }

  static Future<bool> _tryOpen(String name, HiveAesCipher cipher) =>
      // 理由同 canOpenWithKey：默认的崩溃恢复会把「解不开」变成
      // 「截断成空 box 并成功」，从而误判为已加密。
      _openProbe(name, cipher);
}
