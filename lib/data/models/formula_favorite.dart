// lib/data/models/formula_favorite.dart
//
// 层级：data/models
// 职责：公式收藏模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'formula_favorite.g.dart';

@HiveType(typeId: 10)
class FormulaFavorite extends HiveObject {
  @HiveField(0)
  final String formulaId;

  @HiveField(1)
  final String profileId;

  @HiveField(2)
  final DateTime createdAt;

  FormulaFavorite({
    required this.formulaId,
    required this.profileId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
