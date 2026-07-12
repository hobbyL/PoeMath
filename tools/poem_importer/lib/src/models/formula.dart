/// A math formula entry from the primary school math curriculum.
class Formula {
  const Formula({
    required this.id,
    required this.category,
    required this.name,
    required this.formulaText,
    required this.formulaLatex,
    required this.grade,
    required this.params,
    required this.memoryTip,
    required this.example,
    required this.relatedFormulas,
  });

  final String id;
  final String category;
  final String name;
  final String formulaText;
  final String formulaLatex;
  final int grade;
  final List<FormulaParam> params;
  final String memoryTip;
  final String example;
  final List<String> relatedFormulas;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'category': category,
      'name': name,
      'formula_text': formulaText,
      'formula_latex': formulaLatex,
      'grade': grade,
      'params': params.map((p) => p.toJson()).toList(),
      'memory_tip': memoryTip,
      'example': example,
      'related_formulas': relatedFormulas,
    };
  }
}

class FormulaParam {
  const FormulaParam({required this.symbol, required this.meaning});

  final String symbol;
  final String meaning;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'symbol': symbol, 'meaning': meaning};
}
