import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';

import '../helpers/textbook_course_fixture.dart';

void main() {
  test('正文页找到整课，认字和写字不受册末字表来源页限制', () {
    final raw = courseFixture();
    final lesson = (raw['lessons'] as List).single as Map;
    for (final category in ['recognitionCharacters', 'writingCharacters']) {
      for (final node in lesson[category] as List) {
        (node as Map)['sources'] = [courseFixtureSource(3)];
      }
    }
    final pack = TextbookCoursePack.fromJson(raw);
    final matched = textbookLessonsForPages(pack, [2]).single;
    expect(matched.id, 'lesson-001');
    expect(
      TextbookContentSection.recognition.targets(matched).single.id,
      'recognition-001',
    );
    expect(
      TextbookContentSection.writing.targets(matched).single.id,
      'writing-001',
    );
    expect(textbookLessonsForPages(pack, [3]).single.id, matched.id);
    expect(textbookLessonsForPages(pack, [1]), isEmpty);
    expect(textbookLessonsForPages(pack, [-1, 0, 4]), isEmpty);
  });

  test('横屏两页及一页多课保留全部课目，重复页不会重复课目', () {
    final raw = courseFixture();
    final other = {
      'id': 'lesson-002',
      'unitId': 'unit-001',
      'title': '白云测试',
      'kind': 'text',
      'lessonNumber': 2,
      'sources': [courseFixtureSource(3)],
      'review': ((raw['lessons'] as List).single as Map)['review'],
      'coverage': {
        for (final category in TextbookCoursePack.categories)
          category: 'notApplicable',
      },
      for (final category in TextbookCoursePack.categories)
        category: <Object?>[],
    };
    (raw['lessons'] as List).add(other);
    (((raw['units'] as List).single as Map)['lessonIds'] as List)
        .add('lesson-002');
    final pack = TextbookCoursePack.fromJson(raw);
    expect(
      textbookLessonsForPages(pack, [2]).map((lesson) => lesson.id),
      ['lesson-001'],
    );
    expect(
      textbookLessonsForPages(pack, [2, 3, 2]).map((lesson) => lesson.id),
      ['lesson-001', 'lesson-002'],
    );
    expect(
      textbookLessonsForPages(pack, [3]).map((lesson) => lesson.id),
      ['lesson-001', 'lesson-002'],
    );
  });
}
