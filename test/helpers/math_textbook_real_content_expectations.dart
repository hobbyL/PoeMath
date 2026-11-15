import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';

// These assertions come from inspecting the pinned original PDF pages. They
// deliberately check printed questions, formulas and drawing edges, rather
// than deriving an expected result from extraction counts or generated drafts.
List<MathTextbookBlock> verifyMathTextbookRealContent(
  MathTextbookCourse course,
  String key,
) {
  final selected = <MathTextbookBlock>[];
  MathTextbookBlock question(
    int page,
    MathTextbookBlockKind kind,
    String number,
  ) {
    final matches = _pageBlocks(
      course,
      page,
    ).where((b) => b.kind == kind && b.exerciseNumber == number).toList();
    expect(matches, hasLength(1), reason: '$key 原书 PDF $page 的 $kind $number');
    final block = matches.single;
    selected.add(block);
    return block;
  }

  const example = MathTextbookBlockKind.example;
  const exercise = MathTextbookBlockKind.exercise;
  switch (key) {
    case '1a':
      final first = question(29, example, '1');
      _drawing(first, 29, topBefore: .15, bottomAfter: .48);
      _formula(first, '3+1=4');
      final practice = _pageBlocks(
        course,
        29,
      ).singleWhere((b) => b.kind == exercise && b.text.startsWith('做一做'));
      selected.add(practice);
      for (final formula in ['2+2=4', '4+1=5', '1+2=3']) {
        _formula(practice, formula);
      }
      break;
    case '1b':
      final first = question(19, example, '3');
      _drawing(first, 19, topBefore: .09, bottomAfter: .5);
      _formula(first, '13-7=');
      question(19, exercise, '2');
      question(19, exercise, '3');
      break;
    case '2a':
      final first = question(17, example, '1');
      _drawing(first, 17, topBefore: .14, bottomAfter: .49);
      expect(
        _expressions(first)
            .whereType<MathTextbookVerticalArithmetic>()
            .any((e) => e.operation == '+' && e.rows.join('|') == '35| 2| 7'),
        isTrue,
        reason: '先写个位7时十位仍是空位，不能变成35+2=7',
      );
      question(17, exercise, '1');
      _drawing(
        question(17, exercise, '2'),
        17,
        topBefore: .73,
        bottomAfter: .92,
      );
      for (final (page, left, right, operation) in [
        (19, '56', '37', '+'),
        (19, '46', '24', '+'),
        (23, '48', '18', '-'),
        (23, '25', '21', '-'),
        (24, '50', '24', '-'),
      ]) {
        expect(
          _pageBlocks(course, page)
              .expand(_expressions)
              .whereType<MathTextbookVerticalArithmetic>()
              .any(
                (e) =>
                    e.operation == operation &&
                    e.rows[0].trim() == left &&
                    e.rows[1].trim() == right &&
                    e.rows[2].trim().isEmpty,
              ),
          isTrue,
          reason: 'PDF $page 的 $left $operation $right 保留待填竖式',
        );
      }
      final observation = course.currentLessons.singleWhere(
        (l) => l.startPage <= 73 && l.endPage >= 76,
      );
      expect(observation.learning!.exercises, hasLength(6));
      for (final number in ['1', '2', '3']) {
        question(75, exercise, number);
      }
      question(76, exercise, '4');
      question(76, exercise, '5');
      break;
    case '2b':
      final first = question(65, example, '3');
      _drawing(first, 65, topBefore: .07, bottomAfter: .68);
      _formula(first, '13÷4=3');
      expect(_expressions(first).whereType<MathTextbookFraction>(), isEmpty);
      _drawing(
        question(65, exercise, '1'),
        65,
        topBefore: .75,
        bottomAfter: .90,
      );
      break;
    case '3a':
      final first = question(66, example, '2');
      _drawing(first, 66, topBefore: .07, bottomAfter: .62);
      expect(
        _expressions(first).whereType<MathTextbookVerticalArithmetic>().any(
          (e) =>
              e.operation == '×' &&
              e.rows.map((row) => row.trim()).join('|') == '16|3|48' &&
              e.annotations.any(
                (a) => a.value == '1' && a.columnFromRight == 1,
              ),
        ),
        isTrue,
      );
      final practice = question(66, exercise, '1');
      expect(
        _expressions(practice).whereType<MathTextbookVerticalArithmetic>().map(
          (e) => '${e.rows[0].trim()}×${e.rows[1].trim()}:${e.rows[2].trim()}',
        ),
        unorderedEquals(['27×2:', '51×5:', '512×4:', '421×3:']),
      );
      break;
    case '3b':
      final first = question(48, example, '2');
      _drawing(first, 48, topBefore: .07, bottomAfter: .76);
      _formula(first, '37×48=');
      expect(first.text, matches(RegExp(r'1\.\s*先')));
      expect(first.text, matches(RegExp(r'2\.\s*再')));
      expect(first.text, matches(RegExp(r'3\.\s*然后')));
      expect(
        _pageBlocks(
          course,
          48,
        ).where((b) => b.kind == exercise && b.exerciseNumber != null),
        isEmpty,
        reason: '框中的1、2、3是例题的计算步骤',
      );
      break;
    case '4a':
      expect(
        _pageBlocks(
          course,
          83,
        ).expand(_expressions).whereType<MathTextbookFraction>(),
        isEmpty,
        reason: '试商、被除数、积和余数均不是分数',
      );
      expect(
        _pageBlocks(
          course,
          83,
        ).where((b) => b.kind == exercise).map((b) => b.exerciseNumber),
        ['1', '2', '3', '4', '5', '6', '7'],
      );
      _drawing(
        question(83, exercise, '1'),
        83,
        topBefore: .16,
        bottomAfter: .24,
      );
      _drawing(
        question(83, exercise, '2'),
        83,
        topBefore: .27,
        bottomAfter: .39,
      );
      _drawing(
        question(83, exercise, '7'),
        83,
        topBefore: .79,
        bottomAfter: .89,
      );
      break;
    case '4b':
      final first = question(78, example, '3');
      _drawing(first, 78, topBefore: .15, bottomAfter: .81);
      expect(first.text, contains('（1）'));
      expect(first.text, contains('（2）'));
      _formula(first, '17.45+15.8+14.69=47.94');
      _formula(first, '50-16.45-18.3=15.25');
      expect(
        _expressions(first).whereType<MathTextbookVerticalArithmetic>(),
        isEmpty,
        reason: '三个加数的竖式不能截成两个加数',
      );
      break;
    case '5a':
      final first = question(34, example, '5');
      _drawing(first, 34, topBefore: .07, bottomAfter: .575);
      _formula(first, '12.6÷0.28=');
      expect(first.text, matches(RegExp(r'1\.\s*先')));
      expect(first.text, matches(RegExp(r'2\.\s*除数')));
      expect(first.text, matches(RegExp(r'3\.\s*然后')));
      question(34, exercise, '1');
      _drawing(
        question(34, exercise, '2'),
        34,
        topBefore: .74,
        bottomAfter: .90,
      );
      break;
    case '5b':
      final first = question(97, exercise, '6');
      expect(
        _expressions(first)
            .whereType<MathTextbookFraction>()
            .map((e) => e.readable),
        unorderedEquals([
          '1/9',
          '5/9',
          '2/9',
          '6/11',
          '3/11',
          '1/11',
          '1/4',
          '1/4',
          '3/4',
          '7/10',
          '1/10',
          '3/10',
          '11/6',
          '7/6',
          '1/6',
          '2/3',
          '1/3',
        ]),
        reason: '原书六道计算式的17个分数逐一保留',
      );
      _drawing(
        question(97, exercise, '7'),
        97,
        topBefore: .21,
        bottomAfter: .35,
      );
      break;
    case '6a':
      expect(
        _pageBlocks(course, 34).any(
          (b) =>
              b.kind == MathTextbookBlockKind.heading &&
              _compact(b.text) == '2.分数除法',
        ),
        isTrue,
      );
      expect(
        _pageBlocks(course, 34).where(
          (b) =>
              b.kind == exercise &&
              b.exerciseNumber == '2' &&
              b.sources.first.top < .18,
        ),
        isEmpty,
        reason: '编号章节标题不是第2题',
      );
      final first = question(34, example, '1');
      _drawing(first, 34, topBefore: .13, bottomAfter: .77);
      expect(
        _expressions(first)
            .whereType<MathTextbookFraction>()
            .map((e) => e.readable),
        containsAll(['4/5', '2/5']),
      );
      break;
    case '6b':
      final cylinder = question(26, example, '4');
      _drawing(cylinder, 26, topBefore: .07, bottomAfter: .59);
      _formula(cylinder, '3.14×20×30=1884');
      expect(
        _expressions(cylinder)
            .whereType<MathTextbookPower>()
            .map((e) => e.readable),
        ['cm²', 'cm²', 'cm²', 'cm²'],
      );
      final proportion = question(64, example, '5');
      _drawing(proportion, 64, topBefore: .13, bottomAfter: .90);
      _formula(proportion, '40÷8=5');
      _formula(proportion, '5×10=50');
      expect(proportion.text, contains('阅读与理解'));
      expect(proportion.text, contains('回顾与反思'));
      expect(_pageBlocks(course, 64).where((b) => b.kind == exercise), isEmpty);
      break;
    default:
      fail('没有原书内容验收：$key');
  }
  for (final block in selected) {
    final lesson = course.currentLessons.singleWhere(
      (l) => l.blocks.any((b) => b.id == block.id),
    );
    if (block.kind == example) {
      expect(
        lesson.learning!.knowledgePoints.any(
          (k) => k.blockIds.contains(block.id),
        ),
        isTrue,
        reason: '例题保留知识点原书来源：$key ${block.id}',
      );
    } else if (block.kind == exercise) {
      expect(
        lesson.learning!.exercises.any((e) => e.blockIds.contains(block.id)),
        isTrue,
        reason: '题组关联完整原书题目：$key ${block.id}',
      );
    }
  }
  return selected;
}

Iterable<MathTextbookBlock> _pageBlocks(MathTextbookCourse course, int page) =>
    course.currentLessons
        .expand((l) => l.blocks)
        .where(
          (b) =>
              b.kind != MathTextbookBlockKind.sourcePage &&
              b.sources.any((s) => s.page == page),
        );

Iterable<MathTextbookExpression> _expressions(MathTextbookBlock block) sync* {
  for (final span in block.spans) {
    if (span.expression case final expression?) yield* _parts(expression);
  }
}

Iterable<MathTextbookExpression> _parts(
  MathTextbookExpression expression,
) sync* {
  yield expression;
  if (expression is MathTextbookSequence) {
    for (final part in expression.parts) {
      yield* _parts(part);
    }
  } else if (expression is MathTextbookMixedNumber) {
    yield expression.fraction;
  }
}

String _compact(String text) =>
    text.replaceAll(RegExp(r'\s'), '').replaceAll('−', '-');

void _formula(MathTextbookBlock block, String formula) => expect(
  _expressions(block).map((e) => _compact(e.readable)),
  contains(formula),
);

void _drawing(
  MathTextbookBlock block,
  int page, {
  required double topBefore,
  required double bottomAfter,
}) {
  final source = block.sources.singleWhere((s) => s.page == page);
  expect(block.sourceLayout, isTrue, reason: '${block.id} 保留完整原书版面');
  expect(source.top, lessThan(topBefore));
  expect(source.bottom, greaterThan(bottomAfter));
}
