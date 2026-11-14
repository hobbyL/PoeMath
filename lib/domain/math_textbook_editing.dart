import 'package:poemath/data/models/math_textbook_course.dart';

/// 输入采用家长熟悉的分数与运算符；解析失败保持原草稿，不把输入当 LaTeX 执行。
MathTextbookExpression parseMathTextbookExpression(String input) {
  if (input.length > 2048) throw const FormatException('算式过长，请分段填写');
  var rest = input.trim();
  final parts = <MathTextbookExpression>[];
  final token = RegExp(
    r'^(?:(\d+)\s*又\s*(\d+)\s*/\s*(\d+)|(\d+)\s*/\s*(\d+)|([a-zA-Z]{1,8})(?:\^([23])|([²³]))|(\d+(?:\.\d+)?|[a-zA-Z]{1,8}|[+\-−×÷=<>≤≥()%:]))',
  );
  while (rest.isNotEmpty) {
    final match = token.firstMatch(rest);
    if (match == null || parts.length >= 128) {
      throw const FormatException('请填写数字、分数、带分数、平方/立方或运算符；其他内容可保留原图并加说明');
    }
    if (match[1] != null) {
      parts.add(
        MathTextbookMixedNumber(
          match[1]!,
          MathTextbookFraction(match[2]!, match[3]!),
        ),
      );
    } else if (match[4] != null) {
      parts.add(MathTextbookFraction(match[4]!, match[5]!));
    } else if (match[6] != null) {
      parts.add(
        MathTextbookPower(
          match[6]!,
          match[7] == '2' || match[8] == '²' ? 2 : 3,
        ),
      );
    } else {
      parts.add(MathTextbookAtom(match[9]!));
    }
    rest = rest.substring(match.end).trimLeft();
  }
  if (parts.isEmpty) throw const FormatException('请填写算式');
  final expression = parts.length == 1
      ? parts.single
      : MathTextbookSequence(parts);
  return MathTextbookExpression.fromJson(expression.toJson());
}

MathTextbookBlock mergeMathTextbookBlocks(
  MathTextbookBlock first,
  MathTextbookBlock second,
) {
  if (first.kind == MathTextbookBlockKind.sourcePage ||
      second.kind == MathTextbookBlockKind.sourcePage) {
    throw const FormatException('整页对照须单独保留');
  }
  final regions = <int, MathTextbookRegion>{};
  for (final source in [...first.sources, ...second.sources]) {
    regions.update(
      source.page,
      (value) => value.merge(source),
      ifAbsent: () => source,
    );
  }
  return MathTextbookBlock.fromJson(
    MathTextbookBlock(
      id: first.id,
      kind: first.kind,
      spans: [
        ...first.spans,
        if (first.spans.isNotEmpty && second.spans.isNotEmpty)
          const MathTextbookSpan.text('\n'),
        ...second.spans,
      ],
      sources: regions.values.toList(),
      warnings: {...first.warnings, ...second.warnings}.toList(),
      exerciseNumber: first.exerciseNumber ?? second.exerciseNumber,
      parentNote: [
        first.parentNote,
        second.parentNote,
      ].where((v) => v.isNotEmpty).join('\n'),
    ).toJson(),
  );
}
