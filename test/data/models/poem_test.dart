// test/data/models/poem_test.dart
//
// 单元测试：Poem 模型的 JSON 序列化/反序列化。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/poem.dart';

void main() {
  group('Poem', () {
    final sampleJson = <String, dynamic>{
      'id': 'poem_core_001',
      'title': '咏鹅',
      'author': '骆宾王',
      'dynasty': '唐',
      'content': '鹅，鹅，鹅，曲项向天歌。\n白毛浮绿水，红掌拨清波。',
      'pinyin': 'é ， é ， é ， qū xiàng xiàng tiān gē 。',
      'layer': 'core',
      'grade': 1,
      'semester': '上',
      'textbook_unit': '语文一年级上·课文3',
      'is_required': true,
      'annotations': [
        {'word': '曲项', 'meaning': '弯着脖子'},
        {'word': '掌', 'meaning': '鹅的脚掌'},
      ],
      'translation': '鹅呀鹅呀鹅呀，弯着脖子对天欢唱。',
      'appreciation': '全诗用词简单明快。',
      'background': '相传为骆宾王童年所作。',
      'famous_lines': ['白毛浮绿水，红掌拨清波'],
      'tags': ['咏物', '动物'],
      'difficulty': 1,
    };

    test('fromJson 正确解析全部字段', () {
      final poem = Poem.fromJson(sampleJson);

      expect(poem.id, 'poem_core_001');
      expect(poem.title, '咏鹅');
      expect(poem.author, '骆宾王');
      expect(poem.dynasty, '唐');
      expect(poem.layer, 'core');
      expect(poem.grade, 1);
      expect(poem.semester, '上');
      expect(poem.isRequired, true);
      expect(poem.annotations.length, 2);
      expect(poem.annotations[0].word, '曲项');
      expect(poem.famousLines, ['白毛浮绿水，红掌拨清波']);
      expect(poem.tags, ['咏物', '动物']);
      expect(poem.difficulty, 1);
    });

    test('fromJson 处理可选字段缺失', () {
      final minimalJson = <String, dynamic>{
        'id': 'poem_test',
        'title': '测试',
        'author': '测试者',
        'dynasty': '现代',
        'content': '测试内容',
      };
      final poem = Poem.fromJson(minimalJson);

      expect(poem.id, 'poem_test');
      expect(poem.pinyin, '');
      expect(poem.layer, 'explore');
      expect(poem.grade, isNull);
      expect(poem.isRequired, false);
      expect(poem.annotations, isEmpty);
      expect(poem.tags, isEmpty);
    });

    test('toJson 与 fromJson 互逆', () {
      final poem = Poem.fromJson(sampleJson);
      final json = poem.toJson();
      final poem2 = Poem.fromJson(json);

      expect(poem2.id, poem.id);
      expect(poem2.title, poem.title);
      expect(poem2.annotations.length, poem.annotations.length);
      expect(poem2.tags, poem.tags);
    });
  });
}
