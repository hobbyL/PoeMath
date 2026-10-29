import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

/// 删除本书时清理学习进度。
///
/// 认一认/写一写进度键是 `textbook_recognition_v1:<digest>` /
/// `textbook_writing_v1:<digest>`，digest 单向不可由 SHA 反查；但进度
/// JSON 顶层保存 `bookId`（即原书 SHA），因此扫描前缀键、解码后比对。
class TextbookProgressCleanup {
  TextbookProgressCleanup({Box<dynamic>? box})
      : _box = box ?? HiveBoxes.settings;
  final Box<dynamic> _box;

  static const recognitionKeyPrefix = 'textbook_recognition_v1:';
  static const writingKeyPrefix = 'textbook_writing_v1:';

  /// 删除两个前缀下 `bookId == bookId` 的进度键，返回删除数量。
  ///
  /// 解码失败或顶层 `bookId` 缺失的键跳过不删，避免误伤未知记录。
  Future<int> deleteBookProgress(String bookId) async {
    final targets = <String>[];
    for (final key in _box.keys.whereType<String>()) {
      final isProgressKey =
          key.startsWith(recognitionKeyPrefix) || key.startsWith(writingKeyPrefix);
      if (!isProgressKey) continue;
      if (_matchesBook(_box.get(key), bookId)) targets.add(key);
    }
    for (final key in targets) {
      await _box.delete(key);
    }
    if (targets.isNotEmpty) {
      AppLogger.d('删除本书清理学习进度 $bookId：${targets.length} 条', tag: 'Textbook');
    }
    return targets.length;
  }

  bool _matchesBook(Object? raw, String bookId) {
    if (raw is! String) return false;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> && json['bookId'] == bookId;
    } on Object {
      return false;
    }
  }
}
