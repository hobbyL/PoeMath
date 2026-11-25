import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';

import 'math_textbook_fixture.dart';

List<MathTextbookPageLayout> exampleBadgePages() {
  final teaching = MathPageFixture(1)
    ..text('1', .12, .15, width: .01, height: .013)
    ..text('把积木按形状分类。', .19, .15, height: .018)
    ..text('可以按不同形状整理积木。', .19, .4, height: .018);
  teaching.regions.add(
    const MathTextbookRegion(
      page: 1,
      left: .103,
      top: .139,
      right: .153,
      bottom: .177,
    ),
  );
  final practice = MathPageFixture(2)
    ..text('做一做', .1, .08, height: .024)
    ..text('1', .12, .22, width: .008, height: .01)
    ..text('把玩具分类。', .19, .22, height: .018);
  practice.regions.add(
    const MathTextbookRegion(
      page: 2,
      left: .11,
      top: .215,
      right: .138,
      bottom: .236,
    ),
  );
  return [teaching.build(), practice.build()];
}

MathTextbookLesson badgeLesson(
  List<MathTextbookPageLayout> pages, {
  bool legacy = false,
}) {
  final lesson = organizeMathTextbookLesson(
    MathTextbookDraftParser(legacyExampleBadges: legacy)
        .parse(title: '自有分类课', startPage: 1, endPage: 2, pages: pages),
  );
  return lesson.edit(learning: seedMathTextbookLearning(lesson));
}
