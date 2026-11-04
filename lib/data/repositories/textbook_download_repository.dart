import 'package:hive/hive.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';

/// 仅本机使用的下载意图，不进入 JSON/WebDAV 备份。
///
/// 只存 PDF 身份；恢复时重新匹配应用内固定版本目录，不持久化任意 URL。
class TextbookDownloadRepository {
  TextbookDownloadRepository({Box<dynamic>? box}) : _providedBox = box;

  static const keyPrefix = 'textbook_download_v1:';
  final Box<dynamic>? _providedBox;
  Box<dynamic> get _box => _providedBox ?? HiveBoxes.meta;

  Set<String> pendingIds() => {
    for (final key in _box.keys.whereType<String>())
      if (key.startsWith(keyPrefix) &&
          Textbook.isValidId(key.substring(keyPrefix.length)) &&
          _box.get(key) == true)
        key.substring(keyPrefix.length),
  };

  Future<void> markPending(String id) {
    if (!Textbook.isValidId(id)) throw const FormatException('教材身份无效');
    return _box.put('$keyPrefix$id', true);
  }

  Future<void> remove(String id) => _box.delete('$keyPrefix$id');
}
