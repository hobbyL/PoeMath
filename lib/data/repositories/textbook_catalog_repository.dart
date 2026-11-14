import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:poemath/data/models/textbook_catalog.dart';

class TextbookCatalogRepository {
  const TextbookCatalogRepository();

  Future<List<TextbookCatalogEntry>> load() async {
    final sources = await Future.wait([
      rootBundle.loadString('assets/data/textbook_catalog.json'),
      rootBundle.loadString('assets/data/math_textbook_catalog.json'),
    ]);
    final entries = <TextbookCatalogEntry>[];
    for (final source in sources) {
      final json = jsonDecode(source) as Map<String, dynamic>;
      if (!const [1, 2].contains(json['schemaVersion'])) {
        throw const FormatException('教材目录版本不支持');
      }
      entries.addAll(
        (json['books'] as List).map(
          (raw) => TextbookCatalogEntry.fromJson(raw as Map<String, dynamic>),
        ),
      );
    }
    final ids = entries.map((entry) => entry.book.pdfSha256).toSet();
    if (ids.length != entries.length) {
      throw const FormatException('教材目录存在重复资源');
    }
    return List.unmodifiable(entries);
  }
}
