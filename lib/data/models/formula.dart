// lib/data/models/formula.dart
//
// 层级：data/models
// 职责：数学公式模型。对应 assets/data/formulas.json。

import 'package:hive/hive.dart';

import 'formula_param.dart';

part 'formula.g.dart';

@HiveType(typeId: 2)
class Formula extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String category;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final String formulaText;

  @HiveField(4)
  final String formulaLatex;

  @HiveField(5)
  final int grade;

  @HiveField(6)
  final List<FormulaParam> params;

  @HiveField(7)
  final String memoryTip;

  @HiveField(8)
  final String example;

  @HiveField(9)
  final List<String> relatedFormulas;

  Formula({
    required this.id,
    required this.category,
    required this.name,
    required this.formulaText,
    required this.formulaLatex,
    required this.grade,
    this.params = const [],
    this.memoryTip = '',
    this.example = '',
    this.relatedFormulas = const [],
  });

  factory Formula.fromJson(Map<String, dynamic> json) {
    return Formula(
      id: json['id'] as String,
      category: json['category'] as String,
      name: json['name'] as String,
      formulaText: json['formula_text'] as String,
      formulaLatex: json['formula_latex'] as String,
      grade: json['grade'] as int,
      params: (json['params'] as List<dynamic>?)
              ?.map((e) => FormulaParam.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      memoryTip: json['memory_tip'] as String? ?? '',
      example: json['example'] as String? ?? '',
      relatedFormulas: (json['related_formulas'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'name': name,
        'formula_text': formulaText,
        'formula_latex': formulaLatex,
        'grade': grade,
        'params': params.map((e) => e.toJson()).toList(),
        'memory_tip': memoryTip,
        'example': example,
        'related_formulas': relatedFormulas,
      };
}
