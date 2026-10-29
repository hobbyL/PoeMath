import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import '../../helpers/textbook_fixture.dart';

class _MockBox extends Mock implements Box<dynamic> {}

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late TextbookRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('textbook_repo_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('books');
    repo = TextbookRepository(box: box);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('关闭重开 Hive 保留书目、阅读位置和核对状态，重导不覆盖原登记', () async {
    final book = textbookFixture();
    await repo.addIfAbsent(book);
    await repo.savePage('child', book, 2);
    await repo.setMatch('child', book.pdfSha256, TextbookMatch.matches);
    await repo.addIfAbsent(textbookFixture(title: '后来文件名'));
    await box.close();
    box = await Hive.openBox<dynamic>('books');
    repo = TextbookRepository(box: box);
    expect(repo.find(book.pdfSha256)!.toJson(), book.toJson());
    expect(repo.list().length, 1);
    expect(repo.reading('child', book.pdfSha256).toJson(),
        {'page': 2, 'match': 'matches'},);
  });

  test('页码边界、档案与不同资源隔离，核对更新不覆盖排队阅读更新', () async {
    final book = textbookFixture();
    final other = textbookFixture(id: List.filled(64, 'b').join());
    await repo.addIfAbsent(book);
    await repo.addIfAbsent(other);
    await Future.wait([
      repo.savePage('child', book, 100),
      repo.setMatch('child', book.pdfSha256, TextbookMatch.differs),
    ]);
    expect(repo.reading('child', book.pdfSha256).toJson(),
        {'page': 3, 'match': 'differs'},);
    expect(repo.reading('parent', book.pdfSha256).page, 1);
    expect(repo.reading('child', other.pdfSha256).page, 1);
    await repo.savePage('child', book, -10);
    expect(repo.reading('child', book.pdfSha256).page, 1);
  });

  test('错误条目隔离，路径身份不匹配与未来 schema 不混入有效书架', () async {
    final book = textbookFixture();
    await repo.addIfAbsent(book);
    final badId = List.filled(64, 'b').join();
    await box.put(
        '${TextbookRepository.bookKeyPrefix}$badId', jsonEncode(book.toJson()),);
    await box.put(
        '${TextbookRepository.bookKeyPrefix}${List.filled(64, 'c').join()}',
        '{bad json',);
    expect(repo.list().map((book) => book.pdfSha256), [book.pdfSha256]);
    expect(() => Textbook.fromJson({...book.toJson(), 'schemaVersion': 2}),
        throwsFormatException,);
    expect(repo.find('../file'), isNull);
  });

  test('写入失败不污染后续队列，失败调用向 UI 报错', () async {
    final mocked = _MockBox();
    final values = <String, dynamic>{};
    when(() => mocked.get(any<Object>()))
        .thenAnswer((call) => values[call.positionalArguments[0]]);
    var attempts = 0;
    when(() => mocked.put(any<Object>(), any<Object>()))
        .thenAnswer((call) async {
      if (++attempts == 1) throw HiveError('disk full');
      values[call.positionalArguments[0] as String] =
          call.positionalArguments[1];
    });
    final failing = TextbookRepository(box: mocked);
    final book = textbookFixture();
    await expectLater(failing.addIfAbsent(book), throwsA(isA<HiveError>()));
    await failing.addIfAbsent(book);
    expect(failing.find(book.pdfSha256)!.title, book.title);
    expect(attempts, 2);
  });

  test('delete 移除书目与全部档案阅读位置，重复删除幂等', () async {
    final book = textbookFixture();
    final other = textbookFixture(id: List.filled(64, 'b').join());
    await repo.addIfAbsent(book);
    await repo.addIfAbsent(other);
    await repo.savePage('child', book, 2);
    await repo.savePage('parent', book, 5);
    await repo.savePage('child', other, 3);
    await repo.setMatch('child', book.pdfSha256, TextbookMatch.matches);

    await repo.delete(book.pdfSha256);

    expect(repo.find(book.pdfSha256), isNull);
    expect(repo.reading('child', book.pdfSha256).page, 1);
    expect(repo.reading('parent', book.pdfSha256).page, 1);
    expect(repo.reading('child', book.pdfSha256).match, TextbookMatch.unchecked);
    // 其他书不受影响。
    expect(repo.find(other.pdfSha256), isNotNull);
    expect(repo.reading('child', other.pdfSha256).page, 3);

    // 重复删除幂等。
    await repo.delete(book.pdfSha256);
    await repo.delete(book.pdfSha256);
    expect(repo.find(book.pdfSha256), isNull);
    expect(repo.find(other.pdfSha256), isNotNull);
    // 真实键已从 box 移除，而不只是 getter 返回默认值。
    expect(
      box.keys.whereType<String>().where(
            (key) => key.endsWith(':${book.pdfSha256}'),
          ),
      isEmpty,
    );
  });
}
