import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'textbook_course_fixture.dart';

/// 写一写测试课程包：单课一个会写字「星」，与认一认 fixture 互相独立。
TextbookCoursePack writingFixture({bool approved = true}) {
  var raw = courseFixture();
  final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
  lesson['writingCharacters'] = [
    {
      ...courseFixtureText('writing-001', '星', ['xīng']),
      'requirement': 'writing',
    },
    {
      ...courseFixtureText('writing-002', '月', ['yuè']),
      'requirement': 'writing',
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