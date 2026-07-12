// lib/data/models/poem_favorite.dart
//
// 层级：data/models
// 职责：诗词收藏模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'poem_favorite.g.dart';

@HiveType(typeId: 6)
class PoemFavorite extends HiveObject {
  @HiveField(0)
  final String poemId;

  @HiveField(1)
  final String profileId;

  @HiveField(2)
  final DateTime createdAt;

  PoemFavorite({
    required this.poemId,
    required this.profileId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
