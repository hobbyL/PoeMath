// test/data/hive/encrypted_box_roundtrip_test.dart
//
// G6 的闸门：加密 box 的磁盘字节必须真的不含明文，且同 key 能完整读回。
//
// 这条测试对应 `prd.md` 问题 8 验收 1（「box 文件不再是明文 JSON」）与
// 验收 4（「异 key 打不开」）。断言直接读 `.hive` 文件的原始字节 —— 不读
// box API，因为「API 能读回」恰恰是加密失效时也会成立的事。

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/data/hive/hive_value_snapshot.dart';
import 'package:poemath/data/hive/migrations/hive_encryption_migration.dart';

/// 明文哨兵：一段绝不会出现在密文里、且容易在字节流里检索的 ASCII。
const String _sentinel = 'POEMATH-PLAINTEXT-SENTINEL-9f3a';
const String _sentinelKey = 'sentinel-key';

/// 真机上 box 里装的是 [HiveObject] 子类（`Poem` / `Author` / …），
/// 而不是测试里惯用的普通 Map。两者在 Hive 内部走**不同的写入分支**：
/// `Keystore.insert` 只对 `value is HiveObjectMixin` 调 `value.init(key, box)`，
/// 而恰恰是这个调用会在「实例已绑定别的 box」时抛错。
///
/// 因此凡是针对迁移的断言，都必须至少有一条用真正的 [HiveObject] 跑 ——
/// 全用 Map 的那批用例对这类 bug 是盲的（见 `HiveObject 迁移` 组）。
class _Note extends HiveObject {
  _Note(this.title, this.body);

  String title;
  String body;

  @override
  String toString() => '_Note($title)';
}

class _NoteAdapter extends TypeAdapter<_Note> {
  @override
  final int typeId = 77;

  @override
  _Note read(BinaryReader reader) =>
      _Note(reader.read() as String, reader.read() as String);

  @override
  void write(BinaryWriter writer, _Note obj) {
    writer.write(obj.title);
    writer.write(obj.body);
  }
}

List<int> _randomKey([int seed = 1]) {
  final r = Random(seed);
  return List<int>.generate(32, (_) => r.nextInt(256));
}

/// 把一个 box 写到磁盘并关闭。
Future<void> _writeBox(
  Directory dir,
  String name,
  Map<dynamic, dynamic> data, {
  HiveCipher? cipher,
}) async {
  final box = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
  await box.putAll(data);
  await box.close();
}

/// 读 `.hive` 文件的原始字节。
Uint8List _rawBytes(Directory dir, String name) =>
    File('${dir.path}/$name.hive').readAsBytesSync();

/// 在字节流里检索子串（用于断言「明文未出现」）。
///
/// 用 UTF-8 而非 ASCII：本文件的 [HiveObject] 用例故意用中文值
/// （贴近真机的诗词数据），`ascii.encode` 遇到中文会直接抛。
bool _containsAscii(Uint8List bytes, String needle) {
  final pattern = utf8.encode(needle);
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var hit = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_enc_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(77)) {
      Hive.registerAdapter(_NoteAdapter());
      HiveValueSnapshot.registerAdapter<_Note>(_NoteAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('加密 box 往返', () {
    test('密文文件不含明文哨兵，同 key 读回一致', () async {
      final key = _randomKey();
      final cipher = HiveAesCipher(key);
      const data = {_sentinelKey: _sentinel, 'n': 42, 'b': true};

      await _writeBox(dir, 'probe', data, cipher: cipher);

      // ① 磁盘上不应出现明文。
      final raw = _rawBytes(dir, 'probe');
      expect(
        _containsAscii(raw, _sentinel),
        isFalse,
        reason: '密文文件里出现了明文哨兵 —— 加密没有真正生效',
      );

      // ② 同 key 读回一致。
      final box =
          await Hive.openBox<dynamic>('probe', encryptionCipher: cipher);
      expect(box.get(_sentinelKey), _sentinel);
      expect(box.get('n'), 42);
      expect(box.get('b'), true);
      await box.close();
    });

    test('明文 box 的字节里**能**找到哨兵（对照，证明检测手段有效）', () async {
      // 没有这条对照，「找不到哨兵」可能只是因为检索方法本身不работает。
      await _writeBox(dir, 'plainprobe', {_sentinelKey: _sentinel});

      expect(
        _containsAscii(_rawBytes(dir, 'plainprobe'), _sentinel),
        isTrue,
      );
    });

    test('异 key 打不开（不是静默返回空数据）', () async {
      final key = _randomKey(1);
      await _writeBox(
        dir,
        'probe',
        {_sentinelKey: _sentinel},
        cipher: HiveAesCipher(key),
      );
      await Hive.close();

      final otherKey = _randomKey(2);
      // 换 key 打开应失败。若这里改成返回空 box，就意味着「密钥错误」
      // 与「数据为空」无法区分，降级路径会误判。
      //
      // 走 canOpenWithKey 而不是直接 openBox：后者失败时会重复上报同一个
      // 错误（Hive 在 hive_impl.dart:118 既 completeError 又 rethrow），
      // 那份多余的会变成 unhandled error 把测试判失败。
      expect(
        await HiveEncryptionMigration.canOpenWithKey('probe', otherKey),
        isFalse,
      );
      // 原 key 仍能开，证明上一条的 false 是「密钥不对」而非「文件坏了」。
      expect(
        await HiveEncryptionMigration.canOpenWithKey('probe', key),
        isTrue,
      );
    });
  });

  group('HiveEncryptionMigration', () {
    test('明文 box 迁移后变密文，且数据完整', () async {
      final key = _randomKey();
      const data = {'a': 1, 'b': 'text', 'c': true};
      await _writeBox(dir, 'mig', data);
      expect(_containsAscii(_rawBytes(dir, 'mig'), 'text'), isTrue);

      final results = await HiveEncryptionMigration.run(
        boxNames: ['mig'],
        key: key,
        boxDir: dir.path,
      );

      expect(results['mig'], BoxMigrationOutcome.migrated);
      expect(_containsAscii(_rawBytes(dir, 'mig'), 'text'), isFalse);
      // 备份文件应已被删除（抽查通过）。
      expect(
        File('${dir.path}/mig.hive${HiveEncryptionMigration.plaintextBackupSuffix}')
            .existsSync(),
        isFalse,
      );

      final box = await Hive.openBox<dynamic>(
        'mig',
        encryptionCipher: HiveAesCipher(key),
      );
      expect(box.get('a'), 1);
      expect(box.get('b'), 'text');
      expect(box.get('c'), true);
      await box.close();
    });

    test('已加密的 box 迁移幂等（判为 alreadyEncrypted，数据不动）', () async {
      final key = _randomKey();
      await _writeBox(dir, 'enc', {'x': 'keep'}, cipher: HiveAesCipher(key));

      final results = await HiveEncryptionMigration.run(
        boxNames: ['enc'],
        key: key,
        boxDir: dir.path,
      );

      expect(results['enc'], BoxMigrationOutcome.alreadyEncrypted);
      final box = await Hive.openBox<dynamic>(
        'enc',
        encryptionCipher: HiveAesCipher(key),
      );
      expect(box.get('x'), 'keep');
      await box.close();
    });

    test('不存在的 box 判为 absent，不建文件', () async {
      final results = await HiveEncryptionMigration.run(
        boxNames: ['ghost'],
        key: _randomKey(),
        boxDir: dir.path,
      );

      expect(results['ghost'], BoxMigrationOutcome.absent);
      expect(File('${dir.path}/ghost.hive').existsSync(), isFalse);
    });

    test('空明文 box（0 字节）判为 empty，不误报为已加密', () async {
      await _writeBox(dir, 'empty', const {});
      expect(
        File('${dir.path}/empty.hive').lengthSync(),
        0,
        reason: '前提：空 box 落盘就是 0 字节文件',
      );

      final results = await HiveEncryptionMigration.run(
        boxNames: ['empty'],
        key: _randomKey(),
        boxDir: dir.path,
      );

      // 0 字节文件用任意 cipher 都能打开（无 frame 可校验），因此不能靠
      // 试开判断。单列 empty 是为了不把它错报成「已加密」。
      expect(results['empty'], BoxMigrationOutcome.empty);
    });

    test('批量迁移覆盖多个 box，逐个独立', () async {
      final key = _randomKey();
      await _writeBox(dir, 'b1', {'v': 'one'});
      await _writeBox(dir, 'b2', {'v': 'two'}, cipher: HiveAesCipher(key));

      final results = await HiveEncryptionMigration.run(
        boxNames: ['b1', 'b2', 'missing'],
        key: key,
        boxDir: dir.path,
      );

      expect(results['b1'], BoxMigrationOutcome.migrated);
      expect(results['b2'], BoxMigrationOutcome.alreadyEncrypted);
      expect(results['missing'], BoxMigrationOutcome.absent);
    });
  });

  group('canOpenWithKey', () {
    test('密文 box 用原 key 可开、异 key 不可开', () async {
      final key = _randomKey(7);
      await _writeBox(dir, 'probe', {'k': 'v'}, cipher: HiveAesCipher(key));
      // `Hive.openBox` 对已打开的 box 直接返回缓存实例、**忽略 cipher**。
      // 不关掉的话下面的「异 key 不可开」会命中缓存而误判为可开。
      await Hive.close();

      expect(
        await HiveEncryptionMigration.canOpenWithKey('probe', key),
        isTrue,
      );
      expect(
        await HiveEncryptionMigration.canOpenWithKey('probe', _randomKey(8)),
        isFalse,
      );
    });

    test('明文 box 用 cipher 打开应返回 false（它没加密）', () async {
      await _writeBox(dir, 'plainprobe', {'k': 'v'});
      await Hive.close();

      expect(
        await HiveEncryptionMigration.canOpenWithKey(
          'plainprobe',
          _randomKey(),
        ),
        isFalse,
      );
    });
  });

  // ── 真机回归：box 里装的是 HiveObject 而不是 Map ─────────────────────
  //
  // **这一组的存在理由**：G6 首次真机验证时，迁移在 `poems` box 上抛
  // `HiveError: The same instance of an HiveObject cannot be stored in two
  // different boxes.`，整条加密迁移失败、数据留在明文，连带 `AppBootstrap`
  // 报「核心存储初始化失败」。而当时**全部单测都是绿的** —— 因为每个用例
  // 往 box 里放的都是普通 Map，`Keystore.insert` 里 `value is HiveObjectMixin`
  // 恒为 false，那个会抛错的 `init` 分支根本没被执行到。
  //
  // 所以这里的断言不能只看「迁移成功」，必须同时钉住「值是真对象、
  // 类型与内容都完整」—— 否则用 Map 冒充对象也能过。
  group('HiveObject 迁移（真机回归）', () {
    test('明文 box 装 HiveObject 时迁移成功，类型与值完整', () async {
      final key = _randomKey();
      final box = await Hive.openBox<dynamic>('objmig');
      await box.putAll({
        'n1': _Note('静夜思', '床前明月光'),
        'n2': _Note('登鹳雀楼', '白日依山尽'),
        'scalar': 42,
        'text': 'plain-value',
      });
      await box.close();

      // 前提：迁移前确实有明文（迁移后要反过来）。
      expect(_containsAscii(_rawBytes(dir, 'objmig'), '床前明月光'), isTrue);

      final results = await HiveEncryptionMigration.run(
        boxNames: ['objmig'],
        key: key,
        boxDir: dir.path,
      );

      // ① 迁移本身必须成功（真机 bug 就卡在这里）。
      expect(
        results['objmig'],
        BoxMigrationOutcome.migrated,
        reason: 'HiveObject 未解绑会让 putAll 抛错，迁移退化为失败',
      );

      // ② 磁盘上不能残留明文。
      final raw = _rawBytes(dir, 'objmig');
      expect(_containsAscii(raw, '床前明月光'), isFalse);
      expect(_containsAscii(raw, 'plain-value'), isFalse);

      // ③ 读回必须是**真对象**（用 Map 冒充会在这里露馅），内容完整。
      final reopened = await Hive.openBox<dynamic>(
        'objmig',
        encryptionCipher: HiveAesCipher(key),
      );
      final n1 = reopened.get('n1');
      expect(n1, isA<_Note>());
      expect((n1 as _Note).title, '静夜思');
      expect(n1.body, '床前明月光');
      final n2 = reopened.get('n2') as _Note;
      expect(n2.title, '登鹳雀楼');
      expect(n2.body, '白日依山尽');
      // 同 box 里的标量不受解绑逻辑影响。
      expect(reopened.get('scalar'), 42);
      expect(reopened.get('text'), 'plain-value');
      await reopened.close();
    });

    test('迁移成功后不留 .plaintext.bak（抽查通过才删留底）', () async {
      final key = _randomKey();
      final backupPath =
          '${dir.path}/objsnap.hive${HiveEncryptionMigration.plaintextBackupSuffix}';
      final box = await Hive.openBox<dynamic>('objsnap');
      await box.putAll({'n': _Note('春晓', '春眠不觉晓')});
      await box.close();

      final results = await HiveEncryptionMigration.run(
        boxNames: ['objsnap'],
        key: key,
        boxDir: dir.path,
      );

      expect(results['objsnap'], BoxMigrationOutcome.migrated);
      // 抽查通过 → 备份应被删除（成功路径不留垃圾）。
      expect(File(backupPath).existsSync(), isFalse);
      // 且磁盘上确实是密文（中文值检索不到）。
      expect(_containsAscii(_rawBytes(dir, 'objsnap'), '春眠不觉晓'), isFalse);

      // 数据仍可读回 —— 备份被删的前提是内容确实写进了密文 box。
      final reopened = await Hive.openBox<dynamic>(
        'objsnap',
        encryptionCipher: HiveAesCipher(key),
      );
      final note = reopened.get('n');
      expect(note, isA<_Note>());
      expect((note as _Note).body, '春眠不觉晓');
      await reopened.close();
    });

    test('临时密文写入失败后完整源文件与留底都可恢复', () async {
      final box = await Hive.openBox<dynamic>('objbak');
      await box.put('n', _Note('春晓', '春眠不觉晓'));
      await box.close();
      final before = _rawBytes(dir, 'objbak');
      final blocker =
          await Directory('${dir.path}/__migration_target_objbak.hive')
              .create();
      final results = await HiveEncryptionMigration.run(
        boxNames: ['objbak'],
        key: _randomKey(),
        boxDir: dir.path,
      );
      expect(results['objbak'], BoxMigrationOutcome.failed);
      expect(_rawBytes(dir, 'objbak'), before);
      expect(
        await File('${dir.path}/objbak.hive.plaintext.bak').readAsBytes(),
        before,
      );
      await blocker.delete();
      final retry = await HiveEncryptionMigration.run(
        boxNames: ['objbak'],
        key: _randomKey(),
        boxDir: dir.path,
      );
      expect(retry['objbak'], BoxMigrationOutcome.migrated);
      final reopened = await Hive.openBox<dynamic>(
        'objbak',
        encryptionCipher: HiveAesCipher(_randomKey()),
        crashRecovery: false,
      );
      expect((reopened.get('n') as _Note).body, '春眠不觉晓');
    });

    test('中断后优先恢复完整明文留底', () async {
      await _writeBox(dir, 'journal', {'n': _Note('春晓', '春眠不觉晓')});
      final file = File('${dir.path}/journal.hive');
      await File('${file.path}.plaintext.bak')
          .writeAsBytes(await file.readAsBytes(), flush: true);
      await file.writeAsBytes([1, 2, 3]);
      final results = await HiveEncryptionMigration.run(
        boxNames: ['journal'],
        key: _randomKey(),
        boxDir: dir.path,
      );
      expect(results['journal'], BoxMigrationOutcome.migrated);
      final box = await Hive.openBox<dynamic>(
        'journal',
        encryptionCipher: HiveAesCipher(_randomKey()),
        crashRecovery: false,
      );
      expect((box.get('n') as _Note).body, '春眠不觉晓');
    });

    test('迁移校验包含 toString 未暴露的字段', () {
      expect(
        HiveValueSnapshot.encode(_Note('相同标题', '原文')),
        isNot(HiveValueSnapshot.encode(_Note('相同标题', '损坏正文'))),
      );
    });

    test('纯标量 box 仍能迁移（解绑逻辑不能误伤无对象场景）', () async {
      final key = _randomKey();
      await _writeBox(dir, 'scalars', {'a': 1, 'b': 'x', 'c': true});

      final results = await HiveEncryptionMigration.run(
        boxNames: ['scalars'],
        key: key,
        boxDir: dir.path,
      );

      expect(results['scalars'], BoxMigrationOutcome.migrated);
      final box = await Hive.openBox<dynamic>(
        'scalars',
        encryptionCipher: HiveAesCipher(key),
      );
      expect(box.get('a'), 1);
      expect(box.get('b'), 'x');
      expect(box.get('c'), true);
      await box.close();
    });
  });
}
