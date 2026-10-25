import 'package:poemath/data/models/textbook_course.dart';

enum TextbookContentSection {
  reading('读一读', 'paragraphs'),
  recognition('认一认', 'recognitionCharacters'),
  recitation('背一背', 'recitations'),
  writing('写一写', 'writingCharacters');

  const TextbookContentSection(this.label, this.category);
  final String label;
  final String category;

  List<TextbookCourseNode> targets(TextbookCourseLesson lesson) =>
      switch (this) {
        reading => lesson.paragraphs,
        recognition => lesson.recognitionCharacters,
        recitation => lesson.recitations,
        writing => lesson.writingCharacters,
      };
}

/// 先按原书来源找到课目，再展示整课内容。生字的来源可能在册末字表。
/// 一页多课或横屏跨课时保留所有匹配，不按生成时的重叠读取范围猜测归属。
List<TextbookCourseLesson> textbookLessonsForPages(
  TextbookCoursePack pack,
  Iterable<int> pages,
) {
  final visible = pages
      .where((page) => page >= 1 && page <= pack.edition.pageCount)
      .toSet();
  bool matches(TextbookCourseNode node) =>
      node.sources.any((source) => visible.contains(source.pdfPage));
  return [
    for (final lesson in pack.lessons)
      if (matches(lesson) || lesson.targets.any(matches)) lesson,
  ];
}
