// lib/data/hive/bootstrap.dart
//
// 层级：data/hive
// 职责：首次启动时从 asset JSON 导入数据到 Hive Box。
//       检查 data_version，版本不匹配则重新导入。

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/author.dart';
import 'package:poemath/data/models/formula.dart';

/// 数据导入回调签名。progress 范围 0.0 ~ 1.0。
typedef BootstrapProgressCallback = void Function(double progress);

class DataBootstrap {
  const DataBootstrap._();

  /// 检查数据版本，必要时执行导入。
  ///
  /// [onProgress] 报告 0.0 → 1.0 进度，供 SplashPage 显示。
  /// 返回 true 表示执行了导入，false 表示跳过。
  static Future<bool> ensureInitialized({
    BootstrapProgressCallback? onProgress,
  }) async {
    final storedVersion =
        HiveBoxes.meta.get(HiveKeys.metaDataVersion) as String?;

    if (storedVersion == AppConstants.dataVersion) {
      // 版本一致，跳过导入
      return false;
    }

    onProgress?.call(0.0);

    // 1. 加载 asset JSON（并行读取）
    final results = await Future.wait([
      _loadJsonList('assets/data/poems_core.json'),
      _loadJsonList('assets/data/poems_extended.json'),
      _loadJsonList('assets/data/poems_explore.json'),
      _loadJsonList('assets/data/authors.json'),
      _loadJsonList('assets/data/formulas.json'),
    ]);
    onProgress?.call(0.3);

    // 2. 导入诗词（合并三层）
    final allPoemMaps = <Map<String, dynamic>>[
      ...results[0],
      ...results[1],
      ...results[2],
    ];
    await _importPoems(allPoemMaps);
    onProgress?.call(0.6);

    // 3. 导入作者
    await _importAuthors(results[3]);
    onProgress?.call(0.8);

    // 4. 导入公式
    await _importFormulas(results[4]);
    onProgress?.call(0.95);

    // 5. 标记首次启动（如果是首次）
    if (HiveBoxes.meta.get(HiveKeys.metaFirstLaunch) == null) {
      await HiveBoxes.meta.put(HiveKeys.metaFirstLaunch, DateTime.now().toIso8601String());
    }

    // 6. 更新数据版本
    await HiveBoxes.meta.put(HiveKeys.metaDataVersion, AppConstants.dataVersion);
    onProgress?.call(1.0);

    return true;
  }

  static Future<List<Map<String, dynamic>>> _loadJsonList(
      String assetPath,) async {
    final jsonString = await rootBundle.loadString(assetPath);
    final decoded = json.decode(jsonString) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  static Future<void> _importPoems(List<Map<String, dynamic>> items) async {
    // 先清空旧数据
    await HiveBoxes.poems.clear();

    final entries = <String, Poem>{};
    for (final map in items) {
      final poem = Poem.fromJson(map);
      entries[poem.id] = poem;
    }
    await HiveBoxes.poems.putAll(entries);
  }

  static Future<void> _importAuthors(List<Map<String, dynamic>> items) async {
    await HiveBoxes.authors.clear();

    final entries = <String, Author>{};
    for (final map in items) {
      final author = Author.fromJson(map);
      entries[author.id] = author;
    }
    await HiveBoxes.authors.putAll(entries);
  }

  static Future<void> _importFormulas(List<Map<String, dynamic>> items) async {
    await HiveBoxes.formulas.clear();

    final entries = <String, Formula>{};
    for (final map in items) {
      final formula = Formula.fromJson(map);
      entries[formula.id] = formula;
    }
    await HiveBoxes.formulas.putAll(entries);
  }
}
