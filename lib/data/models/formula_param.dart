// lib/data/models/formula_param.dart
//
// 层级：data/models
// 职责：公式参数子模型（嵌入 Formula 内）。

import 'package:hive/hive.dart';

part 'formula_param.g.dart';

@HiveType(typeId: 4)
class FormulaParam extends HiveObject {
  @HiveField(0)
  final String symbol;

  @HiveField(1)
  final String meaning;

  FormulaParam({
    required this.symbol,
    required this.meaning,
  });

  factory FormulaParam.fromJson(Map<String, dynamic> json) {
    return FormulaParam(
      symbol: json['symbol'] as String,
      meaning: json['meaning'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'meaning': meaning,
      };
}
