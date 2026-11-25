import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';

bool canRepairMathTextbookExamples(MathTextbookLesson lesson) {
  final learning = lesson.learning;
  return lesson.review == null &&
      learning != null &&
      !learning.coverageConfirmed &&
      lesson.blocks.any(
        (block) =>
            block.kind == MathTextbookBlockKind.exercise &&
            block.exerciseNumber != null,
      ) &&
      textbookContentDigest(learning.toJson()) ==
          textbookContentDigest(
            seedMathTextbookLearning(
              lesson,
              unitTitle: learning.unitTitle,
            ).toJson(),
          );
}

/// Only a complete reproduction of the previous automatic lesson can change.
/// Authored text, crops, order, answers and review state remain authoritative.
MathTextbookLesson repairMathTextbookExamples(
  MathTextbookLesson lesson,
  List<MathTextbookPageLayout> pages, {
  required String bookId,
}) {
  if (!canRepairMathTextbookExamples(lesson) ||
      pages.any((page) => !page.graphics.complete)) {
    return lesson;
  }
  MathTextbookLesson build({required bool legacy}) {
    final parsed = organizeMathTextbookLesson(
      MathTextbookDraftParser(legacyExampleBadges: legacy).parse(
        title: lesson.title,
        startPage: lesson.startPage,
        endPage: lesson.endPage,
        pages: pages,
      ),
    );
    return parsed.edit(
      learning: seedMathTextbookLearning(
        parsed,
        unitTitle: lesson.learning!.unitTitle,
      ),
    );
  }

  final digest = lesson.contentDigest(bookId);
  if (build(legacy: true).contentDigest(bookId) != digest) return lesson;
  final repaired = build(legacy: false);
  return repaired.contentDigest(bookId) == digest ? lesson : repaired;
}
