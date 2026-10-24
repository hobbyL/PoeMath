import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';

/// 本机书目和续读信息，不进入现有 App JSON/WebDAV 备份白名单。
class TextbookRepository {
  TextbookRepository({Box<dynamic>? box}) : _box = box ?? HiveBoxes.settings;
  final Box<dynamic> _box;
  static const bookKeyPrefix = 'textbook_book_v1:';
  static const readingKeyPrefix = 'textbook_reading_v1:';
  Future<void> _writes = Future<void>.value();

  List<Textbook> list() {
    final books = <Textbook>[];
    for (final key in _box.keys.whereType<String>()) {
      if (!key.startsWith(bookKeyPrefix)) continue;
      final book = find(key.substring(bookKeyPrefix.length));
      if (book != null) books.add(book);
    }
    return books..sort((a, b) => b.importedAt.compareTo(a.importedAt));
  }

  Textbook? find(String id) {
    if (!Textbook.isValidId(id)) return null;
    final raw = _box.get('$bookKeyPrefix$id');
    if (raw == null) return null;
    try {
      final book =
          Textbook.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
      return book.pdfSha256 == id ? book : null;
    } on Object catch (error) {
      AppLogger.e('教材登记信息无法读取', tag: 'Textbook', error: error);
      return null;
    }
  }

  Future<void> addIfAbsent(Textbook book) => _enqueue(() async {
        // 同一文件重导不覆盖原书登记或阅读位置。
        if (find(book.pdfSha256) != null) return;
        final validated = Textbook.fromJson(book.toJson());
        await _box.put(
          '$bookKeyPrefix${book.pdfSha256}',
          jsonEncode(validated.toJson()),
        );
      });

  String _readingKey(String profileId, String id) =>
      '$readingKeyPrefix${Uri.encodeComponent(profileId)}:$id';

  TextbookReading reading(String profileId, String id) {
    final raw = _box.get(_readingKey(profileId, id));
    if (raw == null) return const TextbookReading();
    try {
      return TextbookReading.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>,
      );
    } on Object catch (error) {
      AppLogger.e('教材阅读位置无法读取', tag: 'Textbook', error: error);
      return const TextbookReading();
    }
  }

  Future<void> savePage(String profileId, Textbook book, int page) =>
      _enqueue(() async {
        final previous = reading(profileId, book.pdfSha256);
        await _box.put(
          _readingKey(profileId, book.pdfSha256),
          jsonEncode(
            TextbookReading(
              page: page.clamp(1, book.pageCount),
              match: previous.match,
            ).toJson(),
          ),
        );
      });

  Future<void> setMatch(String profileId, String id, TextbookMatch match) =>
      _enqueue(() async {
        final previous = reading(profileId, id);
        await _box.put(
          _readingKey(profileId, id),
          jsonEncode(
            TextbookReading(page: previous.page, match: match).toJson(),
          ),
        );
      });

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
