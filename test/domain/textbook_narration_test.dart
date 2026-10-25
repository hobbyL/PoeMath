import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_narration.dart';
import '../helpers/textbook_course_fixture.dart';

List<TextbookCourseLesson> lessons(List<String> paragraphs) {
  final raw = courseFixture();
  final lesson = (raw['lessons'] as List).single as Map;
  lesson['paragraphs'] = [
    for (final (index, text) in paragraphs.indexed)
      courseFixtureText('paragraph-$index', text, null),
  ];
  lesson['recitations'] = <Object>[];
  (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
  return TextbookCoursePack.fromJson(raw).lessons;
}

void main() {
  test('完整句分段保留标点和真实英文，排除独立注音', () {
    final input = lessons(['　 星𠀀，月。A, B！“一起回家。”']);
    final result =
        buildTextbookNarration(input, firstTarget: 5, target: 5, softLimit: 10);
    expect(result.map((s) => s.text), ['星𠀀，月。', 'A, B！', '“一起回家。”']);
    expect(result.first.spans.single.start, 2);
    expect(result.first.spans.single.end, 7);
    expect(result.last.spans.single.end,
        input.single.paragraphs.single.text.runes.length,);
  });
  test('未完句跨模型段落，不按逗号或换行截断', () {
    final result = buildTextbookNarration(
      lessons(['孩子望着天空，', '看见白云在飘。然后笑了。']),
      firstTarget: 4,
      target: 4,
      softLimit: 40,
    );
    expect(result.map((s) => s.text), ['孩子望着天空，\n看见白云在飘。', '然后笑了。']);
    expect(result.first.spans.map((s) => s.paragraphId),
        ['paragraph-0', 'paragraph-1'],);
    expect(result.first.spans.last.end, 7);
  });
  test('超过软上限的完整长句保持完整，较短末句合并', () {
    final long = '${List.filled(150, '春').join()}。';
    final result = buildTextbookNarration(lessons([long, '星。月。']),
        firstTarget: 4, target: 4,);
    expect(result.map((s) => s.text), [long, '星。月。']);
  });
  test('源码范围无重复遗漏，Unicode 索引不使用 UTF16', () {
    final input = lessons(['𠀀在看月。孩子笑了！', '云很白。鸟在飞。']);
    final result =
        buildTextbookNarration(input, firstTarget: 4, target: 4, softLimit: 8);
    final actual = <String>[];
    for (final segment in result) {
      for (final span in segment.spans) {
        final p =
            input.single.paragraphs.firstWhere((p) => p.id == span.paragraphId);
        actual.addAll(p.text.runes
            .skip(span.start)
            .take(span.end - span.start)
            .map(String.fromCharCode),);
      }
    }
    expect(actual.join(), input.single.paragraphs.map((p) => p.text).join());
    expect(result.first.spans.single.end, 5);
  });
}
