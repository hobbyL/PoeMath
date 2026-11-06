import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/picture_story_evaluation.dart';

import '../../helpers/picture_story_feedback_fixture.dart';

void main() {
  PictureStoryEvaluation parse(Map<String, Object?> value) =>
      PictureStoryEvaluation.parse(
        jsonEncode(value),
        answer: '小猫坐在窗前。\n它看着小鸟。',
        questionCount: 2,
      );
  Map<String, Object?> fixture() =>
      pictureStoryFeedbackFixture(answer: '小猫坐在窗前。');

  test('三项与逐题结果排序且答案、原题随结果持久化，允许遗漏和不确定', () {
    final value = fixture();
    final dims = value['dimensions'] as List;
    (dims.first as Map).addAll(<String, String>{
      'status': 'uncertain',
      'evidence': '',
    });
    value['dimensions'] = dims.reversed.toList();
    final result = parse(value);
    expect(result.dimensions.map((d) => d.id), [
      'picture',
      'response',
      'expression',
    ]);
    expect(result.dimensions.first.status, PictureStoryAssessment.uncertain);
    expect(result.questions.first.evidence, '');
    final saved = jsonDecode(
      result.encode(answer: '小猫坐在窗前。\n它看着小鸟。', prompts: ['哪里', '动作']),
    );
    expect(saved['answer'], '小猫坐在窗前。\n它看着小鸟。');
    expect(saved['prompts'], ['哪里', '动作']);
  });

  test('拒绝编造、拼接原话和缺少证据的肯定判断', () {
    for (final evidence in ['小猫坐在草地。', '小猫坐在窗前。它看着小鸟。', '']) {
      final value = fixture();
      ((value['dimensions'] as List).first as Map)['evidence'] = evidence;
      expect(() => parse(value), throwsFormatException);
    }
  });

  test('拒绝漏项、重复项、不认识的状态及问题编号', () {
    final incomplete = fixture()..['questions'] = [];
    expect(() => parse(incomplete), throwsFormatException);
    for (final change in [
      {'id': 'response'},
      {'status': 'correct'},
    ]) {
      final value = fixture();
      ((value['dimensions'] as List).first as Map).addAll(change);
      expect(() => parse(value), throwsFormatException);
    }
    final invalidId = fixture();
    ((invalidId['questions'] as List).first as Map)['id'] = '3';
    expect(() => parse(invalidId), throwsFormatException);
  });

  test('修改建议有真实原句且最多两条，结构和长度也必须有效', () {
    final value = fixture();
    final suggestion = {
      'original': '它看着小鸟。',
      'replacement': '它望着窗外的小鸟。',
      'reason': '说明观察的方向。',
    };
    value['suggestions'] = [suggestion];
    expect(parse(value).suggestions.single.original, '它看着小鸟。');
    value['suggestions'] = [suggestion, suggestion, suggestion];
    expect(() => parse(value), throwsFormatException);
    value['suggestions'] = [
      {...suggestion, 'original': '小猫跑了。'},
    ];
    expect(() => parse(value), throwsFormatException);
    value['suggestions'] = [];
    value['summary'] = '字' * 401;
    expect(() => parse(value), throwsFormatException);
    expect(
      () =>
          PictureStoryEvaluation.parse('不是JSON', answer: '', questionCount: 0),
      throwsFormatException,
    );
  });
}
