import 'dart:math';

import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;
import 'package:poemath/domain/math_textbook_practice.dart';

typedef MathTextbookPreparedPractice = ({
  int? seed,
  List<MathTextbookPracticeItem> items,
});

/// Cache question content independently of each child's answers/session. The
/// default seed survives new rounds; an older draft still uses its frozen seed.
Future<MathTextbookPreparedPractice> prepareMathTextbookPractice({
  required TextbookContentCache cache,
  required Textbook book,
  required MathTextbookLesson lesson,
  MathTextbookPracticePlan? plan,
  int? seed,
  List<MathTextbookPracticeItem> Function(int? seed)? generate,
}) async {
  if (cache.book.pdfSha256 != book.pdfSha256) {
    throw const FormatException('教材题组缓存不属于本书');
  }
  final revision = cache.revision;
  void check() {
    if (cache.revision != revision) throw StateError('原书缓存已失效');
  }

  final identity = {
    'kind': 'math-practice',
    'version': 1,
    'lesson': lesson.contentDigest(book.pdfSha256),
    'plan': plan?.digest,
    'grade': book.grade,
    'semester': book.semester,
  };
  if (plan != null && seed == null) {
    seed = await cache.mathData<int>(
      textbookContentDigest({...identity, 'part': 'seed'}),
      decode: (value) {
        if (value is! int || value < 0 || value > 2147483647) {
          throw const FormatException('教材题组缓存标识无效');
        }
        return value;
      },
      encode: (value) => value,
      load: () async => Random.secure().nextInt(2147483647),
    );
  }
  check();
  final selectedSeed = seed;
  final count = plan == null
      ? lesson.learning?.exercises.length ?? 0
      : plan.kind == MathTextbookPracticeKind.parentTask
      ? 1
      : plan.count;
  final items = await cache.mathData<List<MathTextbookPracticeItem>>(
    textbookContentDigest({...identity, 'part': 'items', 'seed': selectedSeed}),
    decode: (raw) {
      if (raw is! List || raw.length != count) {
        throw const FormatException('教材题组缓存无效');
      }
      final items = raw.map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('教材题目缓存无效');
        }
        return MathTextbookPracticeItem.fromJson(value);
      }).toList();
      if (items.map((item) => item.exercise.id).toSet().length !=
              items.length ||
          items
              .expand((item) => item.blocks)
              .expand((block) => block.sources)
              .any(
                (source) =>
                    source.page < lesson.startPage ||
                    source.page > lesson.endPage,
              )) {
        throw const FormatException('教材题组缓存范围无效');
      }
      return List.unmodifiable(items);
    },
    encode: (items) => items.map((item) => item.toJson()).toList(),
    load: () async => List.unmodifiable(
      generate?.call(selectedSeed) ??
          (plan == null
              ? originalMathTextbookItems(lesson)
              : generateMathTextbookPractice(
                  lesson: lesson,
                  plan: plan,
                  grade: book.grade,
                  semester: book.semester,
                  random: Random(selectedSeed!),
                )),
    ),
  );
  check();
  return (seed: selectedSeed, items: items);
}
