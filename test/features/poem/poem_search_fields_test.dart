// test/features/poem/poem_search_fields_test.dart
//
// 诗词搜索扩字段测试（任务 10-12-feature-batch-8 ②）：
// - 搜索名句片段命中对应诗（famousLines）；
// - 搜索标签词命中（tags，如「思乡」）；
// - 标题/正文/作者原三元组行为不回归；
// - 名句与标签都不含关键词时按原逻辑过滤。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

import '../../helpers/hive_test_helper.dart';

const _kPoemA = 'search-a';
const _kPoemB = 'search-b';
const _kPoemC = 'search-c';

Poem _poem(String id, {List<String> famousLines = const [], List<String> tags = const []}) {
  return Poem(
    id: id,
    title: '诗$id',
    author: '作者$id',
    dynasty: '唐',
    content: '正文$id 第一行',
    pinyin: '',
    layer: 'core',
    grade: 1,
    famousLines: famousLines,
    tags: tags,
  );
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    HiveBoxes.poems.put(
      _kPoemA,
      _poem(
        _kPoemA,
        famousLines: const ['举头望明月，低头思故乡'],
        tags: const ['思乡', '月亮'],
      ),
    );
    HiveBoxes.poems.put(_kPoemB, _poem(_kPoemB, tags: const ['春天']));
    HiveBoxes.poems.put(_kPoemC, _poem(_kPoemC));
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  List<String> search(ProviderContainer container, String query) {
    container.read(poemSearchQueryProvider.notifier).state = query;
    return container.read(filteredPoemsProvider).map((p) => p.id).toList();
  }

  test('搜索名句片段命中对应诗', () {
    final container = makeContainer();
    expect(search(container, '低头思故乡'), [_kPoemA]);
    expect(search(container, '举头望明月'), [_kPoemA]);
  });

  test('搜索标签词命中（思乡）', () {
    final container = makeContainer();
    expect(search(container, '思乡'), [_kPoemA]);
    expect(search(container, '春天'), [_kPoemB]);
  });

  test('标题/正文/作者三元组行为不回归', () {
    final container = makeContainer();
    expect(search(container, '诗search-a'), [_kPoemA]);
    expect(search(container, '正文search-b'), [_kPoemB]);
    expect(search(container, '作者search-c'), [_kPoemC]);
  });

  test('名句与标签都不含关键词时按原逻辑过滤', () {
    final container = makeContainer();
    expect(search(container, '不存在'), isEmpty);
  });
}
