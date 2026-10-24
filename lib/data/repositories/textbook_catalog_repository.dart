import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:poemath/data/models/textbook_catalog.dart';

class TextbookCatalogRepository {
  const TextbookCatalogRepository();

  Future<List<TextbookCatalogEntry>> load() async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/data/textbook_catalog.json'),
    ) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('教材目录版本不支持');
    }
    final entries = (json['books'] as List)
        .map(
            (raw) => TextbookCatalogEntry.fromJson(raw as Map<String, dynamic>),)
        .toList();
    final ids = entries.map((entry) => entry.book.pdfSha256).toSet();
    if (ids.length != entries.length) {
      throw const FormatException('教材目录存在重复资源');
    }
    return List.unmodifiable(entries);
  }
}
