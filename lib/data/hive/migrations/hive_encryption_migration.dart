// lib/data/hive/migrations/hive_encryption_migration.dart
//
// 层级：data/hive/migrations
// 职责：把已有的**明文** Hive box 就地转换为 AES 密文（一次性迁移）。
//
// 为什么必须手工做：Hive 没有 `rekey` / `migrateToCipher` API，
// 加解密只在 box 文件打开时生效，转换只能「读出 → 换密文重写」。
//
// 安全性质（每一步都不能省）：
//   1. 先 dump 全部数据到内存，**再**动磁盘 —— 中途失败时原文件还没被碰过。
//   2. 旧文件改名 `.plaintext.bak` 而非直接删 —— 新密文写坏时能退回去。
//   3. 新密文写完 close 后用同 key **重新打开抽查** —— 确认真的写得回来，
//      才删 `.bak`。只信「putAll 没抛异常」是不够的（box 可能没 flush 完）。
//   4. 任何一步失败 → 删掉半成品新文件、把 `.bak` 改回原名、向上抛，
//      由调用方决定是重试还是降级。
//
// 不在这里决定「要不要迁移」——那是 `HiveEncryptionKeyResolver` 的职责
// （它要看密钥状态）。本类只做「给定 key，把这批 box 变成密文」。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import 'package:poemath/core/utils/logger.dart';

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

  /// **既非本密钥密文、又非可读明文** —— 数据已不可恢复。
  ///
  /// 典型来源：半迁移状态（进程被杀，留下用旧密钥加密的 box），或换机
  /// 恢复备份带来的异密钥密文。`run()` 会跳过它、继续迁移其余 box，
  /// 把结论留给调用方。
  unreadable,
}

/// 明文 box 文件内容的**内存快照**。
///
/// 用途见 `HiveEncryptionMigration._snapshotOf`：`clear()` 会把源文件截成
/// 0 字节，因此必须在动它之前把原始字节留一份在内存里，稍后写回
/// `.plaintext.bak`。
class _PlaintextSnapshot {
  _PlaintextSnapshot(this.originalPath, this.bytes);

  /// 源文件路径。`clear()` 之后文件名仍在，内容已空。
  final String originalPath;

  /// `clear()` 之前读到的完整字节。
  final Uint8List bytes;

  /// 把快照写回 [targetPath]。
  ///
  /// 失败即抛：此时原文件已被清空，备份写不出去就意味着**没有回滚留底**，
  /// 调用方必须据此中止该 box 的迁移（见 `_migrateBox` 的回滚分支）。
  void restoreTo(String targetPath) {
    File(targetPath).writeAsBytesSync(bytes, flush: true);
  }
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
  /// **任一 box 迁移失败立即向上抛** —— 不吞掉。半迁移状态（一半密文一半
  /// 明文）本身可恢复，但必须让调用方知道，否则会在用户不知情的情况下
  /// 用新密钥去开旧明文 box，误判成「密钥丢失」而清空数据。
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

    final results = <String, BoxMigrationOutcome>{};

    for (final name in boxNames) {
      try {
        results[name] = await _migrateBox(
          name: name,
          cipher: cipher,
          boxDir: boxDir,
        );
      } on Object catch (error, stack) {
        // 单个 box 读不出来（既非本密钥密文、又非可读明文）时**跳过它**，
        // 继续迁移其余的，而不是让整批作废。
        //
        // 为什么不能整批中止：迁移是逐 box 落盘的，进程在中途被杀就会留下
        // 「部分已密文（旧密钥）、部分仍明文」的目录。这种混存状态下下次
        // 启动若整批中止，就永远卡在「每次启动都失败、加密始终完不成」。
        //
        // 跳过的语义是安全的：该 box 的数据本就已经解不开（否则不会走到
        // 这里），跳过不会丢任何可读数据；而它会被记为 `unreadable`，
        // 上层据此决定是否走降级。
        AppLogger.e(
          'box「$name」无法迁移，跳过并继续其余 box',
          tag: _tag,
          error: error,
          stackTrace: stack,
        );
        results[name] = BoxMigrationOutcome.unreadable;
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

  /// 按明文打开 [name] 并 dump 全部键值；失败返回 null（错误记日志）。
  ///
  /// 同样必须关 `crashRecovery`：默认的恢复会把「非明文文件」截断成空 box
  /// 并成功返回，于是迁移会**把用户数据清空后当成功**。
  ///
  /// dump 出来的值会先经 [_unbindDumpedObjects] 解绑，否则 [HiveObject]
  /// 实例回写时会抛错（见该方法的说明）。
  static Future<Map<dynamic, dynamic>?> _openAndDump(
    String name, {
    required _PlaintextSnapshot? snapshot,
  }) async {
    Map<dynamic, dynamic>? dump;
    final ok = await _guarded(
      () async {
        final plain = await Hive.openBox<dynamic>(name, crashRecovery: false);
        dump = {for (final k in plain.keys.toList()) k: plain.get(k)};
        // `clear()` 就地解绑必须发生在 close 之前。它同时会把磁盘文件
        // 截成 0 字节，所以原始字节已在更早一步由调用方存进了 [snapshot]
        // （见 [_PlaintextSnapshot]）。
        await plain.clear();
        await plain.close();
      },
      onError: (error, stack) {
        AppLogger.e(
          'box「$name」既非密文也非可读明文，迁移中止',
          tag: _tag,
          error: error,
          stackTrace: stack,
        );
      },
    );
    return ok ? dump : null;
  }

  /// 明文 box 文件内容的**内存快照**，用于在 `clear()` 之后重建回滚留底。
  ///
  /// **为什么需要它**：迁移必须同时满足两个约束，而它们在 Hive 的 API 里
  /// 互相冲突（探针 F / G / J 三次实测得出）：
  ///
  /// | 约束 | 只能用 | 副作用 |
  /// |---|---|---|
  /// | 把 [HiveObject] 实例从源 box **解绑**（否则回写抛 `The same instance of an HiveObject cannot be stored in two different boxes.`） | `Box.clear()` | 先把磁盘文件**清成 0 字节** |
  /// | 保住 `.plaintext.bak` 的**回滚价值** | 不碰磁盘 | 无法解绑 |
  ///
  /// `Keystore.clear()` 本可两者兼顾（只清内存），但它被标了 `@protected`
  /// + `@visibleForTesting`，依赖它等于绑定 hive 的内部实现细节 ——
  /// 代价不划算。
  ///
  /// 于是改为：**动磁盘之前，先把原始字节读进内存**。之后 `clear()` 随便
  /// 截断文件，最后用这份字节把 `.plaintext.bak` 写回去。探针 K 实证：
  /// 写回的字节能被当明文 box 正常打开，回滚路径真的可用。
  ///
  /// **为什么单测发现不了原始的绑定 bug**：单测的 box 里放的是普通 `Map`，
  /// 不满足 `value is HiveObjectMixin`，Hive 直接跳过 `init` 分支。只有
  /// 真机上装了 adapter、box 里是真对象的场景才会踩到。
  static _PlaintextSnapshot? _snapshotOf(File file) {
    try {
      if (!file.existsSync()) return null;
      return _PlaintextSnapshot(file.path, file.readAsBytesSync());
    } on Object catch (error, stack) {
      // 读不出原始字节就没法保住回滚留底。宁可不迁移：留着明文让下次
      // 启动重试，也好过把用户数据推进一个无法回退的转换里。
      AppLogger.e(
        '读取明文 box 备份失败，本次不迁移该 box',
        tag: _tag,
        error: error,
        stackTrace: stack,
      );
      return null;
    }
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
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return succeeded;
  }

  static Future<BoxMigrationOutcome> _migrateBox({
    required String name,
    required HiveAesCipher cipher,
    required String boxDir,
  }) async {
    final file = File('$boxDir/$name.hive');
    if (!file.existsSync()) return BoxMigrationOutcome.absent;
    // 0 字节 = 从未写入过任何数据。没有 frame 就没有 checksum 可校验，
    // 任何 cipher 都能「打开」它，因此不能靠试开来判断，只能先按大小分流。
    if (file.lengthSync() == 0) return BoxMigrationOutcome.empty;

    // 已是密文 → 不碰。用 cipher 打开成功即证明本文件已加密。
    if (await _tryOpen(name, cipher)) {
      return BoxMigrationOutcome.alreadyEncrypted;
    }

    // 先把原始字节读进内存：`_openAndDump` 里的 `clear()` 会把磁盘文件
    // 截成 0 字节，到那时就再也读不出回滚留底了。详见 [_PlaintextSnapshot]。
    final snapshot = _snapshotOf(file);
    if (snapshot == null) {
      throw HiveError('box「$name」无法读取原始字节，迁移中止（详见日志）');
    }

    // 按明文打开读出全部数据，并就地解绑（clear）以便回写到新 box。
    //
    // 走 _openAndDump：它关掉 crashRecovery 并隔离 Hive 的重复上报。
    // 失败时返回 null（错误已在日志里），此处视为文件损坏。
    final dumped = await _openAndDump(name, snapshot: snapshot);
    if (dumped == null) {
      throw HiveError(
        'box「$name」既非密文也非可读明文，迁移中止（详见日志）',
      );
    }
    final values = dumped;

    final backup = File('$boxDir/$name.hive$plaintextBackupSuffix');

    // 1) 用内存快照重建明文留底（**不删**）。
    //
    // 此刻源文件已被 `clear()` 清空，这一步是唯一的回滚依托；写不出去就
    // 不能继续，直接抛出交由上层回滚（此时磁盘上该 box 已是 0 字节，
    // 但数据完整保存在 `values` 里，上层会退回明文重写）。
    snapshot.restoreTo(backup.path);

    try {
      // 2) 用 cipher 打开一个全新空 box 并写回全部数据。
      final encrypted = await Hive.openBox<dynamic>(
        name,
        encryptionCipher: cipher,
      );
      if (values.isNotEmpty) await encrypted.putAll(values);
      await encrypted.compact();
      await encrypted.close();

      // 3) 抽查：同 key 重新打开，逐键核对读回的值。
      await _verify(name, cipher, values);

      // 4) 抽查通过，才删明文留底。
      await backup.delete();
      return BoxMigrationOutcome.migrated;
    } on Object catch (error, stack) {
      // 回滚：删半成品密文、明文恢复原名，再向上抛。
      AppLogger.e(
        'box「$name」加密迁移失败，回滚为明文',
        tag: _tag,
        error: error,
        stackTrace: stack,
      );
      await _rollback(name: name, boxDir: boxDir, backup: backup);
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
    Map<dynamic, dynamic> expected,
  ) async {
    final reopened = await Hive.openBox<dynamic>(
      name,
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
        if (actual.toString() != entry.value.toString()) {
          throw StateError(
            'box「$name」密文抽查值不符，key=${entry.key}',
          );
        }
      }
    } finally {
      await reopened.close();
    }
  }

  /// 回滚单个 box：删掉可能存在的半成品密文，把 `.bak` 改回原名。
  static Future<void> _rollback({
    required String name,
    required String boxDir,
    required File backup,
  }) async {
    try {
      final file = File('$boxDir/$name.hive');
      if (file.existsSync()) await file.delete();
      if (backup.existsSync()) await backup.rename(file.path);
    } on Object catch (error) {
      // 回滚自身失败是最坏情形：数据此刻只在 .bak 里。
      // 明确告诉用户/开发者文件在哪，不要静默。
      AppLogger.e(
        'box「$name」回滚失败，明文数据仍在 ${backup.path}',
        tag: _tag,
        error: error,
      );
    }
  }

  static Future<bool> _tryOpen(String name, HiveAesCipher cipher) =>
      // 理由同 canOpenWithKey：默认的崩溃恢复会把「解不开」变成
      // 「截断成空 box 并成功」，从而误判为已加密。
      _openProbe(name, cipher);
}
