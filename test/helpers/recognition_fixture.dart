import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'textbook_course_fixture.dart';

TextbookCoursePack recognitionFixture({bool approved = true}) {
  var raw = courseFixture();
  final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
  lesson['recognitionCharacters'] = [
    for (final entry in [
      ('recognition-001', '𠀀', 'hē'),
      ('star', '星', 'xīng'),
      ('moon', '月', 'yuè'),
      ('go', '行', 'xíng'),
      ('form', '形', 'xíng'),
    ])
      {
        ...courseFixtureText(entry.$1, entry.$2, [entry.$3]),
        'requirement': 'recognition',
      },
  ];
  if (approved) {
    final pack = TextbookCoursePack.fromJson(raw);
    for (final node in [pack.lessons.single, ...pack.lessons.single.targets]) {
      raw = reviewTextbookCourse(
        input: raw,
        nodeId: node.id,
        reviewer: '测试家长',
        decision: 'approved',
        checks: node.requiredChecks,
        notes: '已核对自有样本',
        at: DateTime.utc(2026, 10, 24),
      );
    }
  }
  return TextbookCoursePack.fromJson(raw);
}
