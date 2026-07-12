// test/data/models/author_test.dart
//
// 单元测试：Author 模型的 JSON 序列化/反序列化。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/author.dart';

void main() {
  group('Author', () {
    test('fromJson 正确解析', () {
      final json = <String, dynamic>{
        'id': 'author_libai',
        'name': '李白',
        'dynasty': '唐',
        'life_years': '701-762',
        'title': '诗仙',
        'brief': '唐代伟大浪漫主义诗人。',
        'representative_works': ['poem_core_001'],
        'avatar': 'default_avatar.png',
      };

      final author = Author.fromJson(json);
      expect(author.name, '李白');
      expect(author.dynasty, '唐');
      expect(author.title, '诗仙');
      expect(author.representativeWorks, ['poem_core_001']);
    });

    test('fromJson 处理缺失字段', () {
      final json = <String, dynamic>{
        'id': 'test',
        'name': '测试',
        'dynasty': '现代',
      };
      final author = Author.fromJson(json);
      expect(author.lifeYears, '');
      expect(author.title, '');
      expect(author.representativeWorks, isEmpty);
    });
  });
}
