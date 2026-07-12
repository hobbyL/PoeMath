// lib/data/models/author.dart
//
// 层级：data/models
// 职责：作者模型。对应 assets/data/authors.json。

import 'package:hive/hive.dart';

part 'author.g.dart';

@HiveType(typeId: 1)
class Author extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String dynasty;

  @HiveField(3)
  final String lifeYears;

  @HiveField(4)
  final String title; // 诗仙、诗圣 等

  @HiveField(5)
  final String brief;

  @HiveField(6)
  final List<String> representativeWorks; // poem IDs

  @HiveField(7)
  final String avatar;

  Author({
    required this.id,
    required this.name,
    required this.dynasty,
    this.lifeYears = '',
    this.title = '',
    this.brief = '',
    this.representativeWorks = const [],
    this.avatar = 'default_avatar.png',
  });

  factory Author.fromJson(Map<String, dynamic> json) {
    return Author(
      id: json['id'] as String,
      name: json['name'] as String,
      dynasty: json['dynasty'] as String,
      lifeYears: json['life_years'] as String? ?? '',
      title: json['title'] as String? ?? '',
      brief: json['brief'] as String? ?? '',
      representativeWorks: (json['representative_works'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      avatar: json['avatar'] as String? ?? 'default_avatar.png',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dynasty': dynasty,
        'life_years': lifeYears,
        'title': title,
        'brief': brief,
        'representative_works': representativeWorks,
        'avatar': avatar,
      };
}
