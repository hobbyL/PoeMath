import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_learning_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

Textbook _book(String id, int grade, String semester) => Textbook.fromJson({
      ...textbookFixture(id: id.padLeft(64, '0')).toJson(),
      'grade': grade,
      'semester': semester,
    });

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('只展示已添加的当前年级学期教材，同册多个版本均保留', () async {
    final repository = TextbookRepository();
    final matching = [_book('a', 3, '上'), _book('b', 3, '上')];
    for (final book in [...matching, _book('c', 3, '下'), _book('d', 4, '上')]) {
      await repository.addIfAbsent(book);
    }
    await SettingsRepository().setLearningBackground(3, '上');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(currentTextbooksProvider).map((book) => book.pdfSha256),
      unorderedEquals(matching.map((book) => book.pdfSha256)),
    );
    expect(container.read(textbookLocalListProvider), hasLength(4));
    container.read(selectedGradeProvider.notifier).state = 4;
    container.read(selectedSemesterProvider.notifier).state = '下';
    expect(container.read(currentTextbooksProvider), hasLength(2));
  });

  test('学习背景保存并失效后立即切换册次，重建容器仍一致', () async {
    final upper = _book('a', 3, '上');
    final lower = _book('b', 4, '下');
    final repository = TextbookRepository();
    await repository.addIfAbsent(upper);
    await repository.addIfAbsent(lower);
    final settings = SettingsRepository();
    await settings.setLearningBackground(3, '上');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(currentTextbooksProvider).single.pdfSha256,
      upper.pdfSha256,
    );
    await settings.setLearningBackground(4, '下');
    invalidateLearningBackground(container.invalidate);
    expect(
      container.read(currentTextbooksProvider).single.pdfSha256,
      lower.pdfSha256,
    );
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(
      restarted.read(currentTextbooksProvider).single.pdfSha256,
      lower.pdfSha256,
    );
  });

  test('无当前册次时返回空列表，不以其他年级代替', () async {
    await TextbookRepository().addIfAbsent(_book('a', 6, '下'));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(currentTextbooksProvider), isEmpty);
    expect(container.read(textbookLocalListProvider), hasLength(1));
  });
}
