// lib/data/repositories/author_repository.dart
//
// 层级：data/repositories
// 职责：作者数据仓储。

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/author.dart';

class AuthorRepository {
  /// 按 ID 获取
  Author? getById(String id) => HiveBoxes.authors.get(id);

  /// 按名字查找（精确匹配）
  Author? getByName(String name) {
    return HiveBoxes.authors.values.cast<Author?>().firstWhere(
          (a) => a?.name == name,
          orElse: () => null,
        );
  }

  /// 获取所有作者
  List<Author> getAll() => HiveBoxes.authors.values.toList();

  /// 按朝代筛选
  List<Author> byDynasty(String dynasty) {
    return HiveBoxes.authors.values
        .where((a) => a.dynasty == dynasty)
        .toList();
  }

  /// 总作者数
  int get totalCount => HiveBoxes.authors.length;
}
