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
  static const recentKeyPrefix = 'textbook_recent_v1:';
  static const selectionKeyPrefix = 'textbook_selection_v1:';
  Future<void> _writes = Future<void>.value();

  String _recentKey(String profileId) =>
      '$recentKeyPrefix${Uri.encodeComponent(profileId)}';

  String _selectionKey(String profileId, TextbookSubject subject) =>
      '$selectionKeyPrefix${Uri.encodeComponent(profileId)}:${subject.name}';

  Textbook? currentBook(String profileId, TextbookSubject subject) {
    final id = _box.get(_selectionKey(profileId, subject));
    if (id is! String) return null;
    final book = find(id);
    return book?.subject == subject ? book : null;
  }

  Future<void> selectBook(String profileId, Textbook book) =>
      _enqueue(() async {
        final current = find(book.pdfSha256);
        if (current == null || current.subject != book.subject) {
          throw const FormatException('本书已移除或学科已变更');
        }
        await _box.put(_selectionKey(profileId, book.subject), book.pdfSha256);
      });

  Textbook? recentBook(String profileId) {
    final id = _box.get(_recentKey(profileId));
    if (id == null) return null;
    if (id is! String || !Textbook.isValidId(id)) {
      throw const FormatException('最近阅读记录无法读取');
    }
    return find(id);
  }

  Future<void> markOpened(String profileId, String id) => _enqueue(() async {
    if (find(id) == null) return;
    await _box.put(_recentKey(profileId), id);
  });

  Stream<BoxEvent> watchReading(String profileId) =>
      _box.watch().where((event) {
        final key = event.key;
        return key is String &&
            (key == _recentKey(profileId) ||
                key.startsWith(
                  '$selectionKeyPrefix${Uri.encodeComponent(profileId)}:',
                ) ||
                key.startsWith(
                  '$readingKeyPrefix${Uri.encodeComponent(profileId)}:',
                ) ||
                key.startsWith(bookKeyPrefix));
      });

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
      final book = Textbook.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>,
      );
      return book.pdfSha256 == id ? book : null;
    } on Object catch (error) {
      AppLogger.e('教材登记信息无法读取', tag: 'Textbook', error: error);
      return null;
    }
  }

  Future<void> addIfAbsent(Textbook book, {void Function()? authorize}) =>
      _enqueue(() async {
        authorize?.call();
        // 同一文件重导不覆盖原书登记或阅读位置。
        if (find(book.pdfSha256) != null) return;
        final validated = Textbook.fromJson(book.toJson());
        await _box.put(
          '$bookKeyPrefix${book.pdfSha256}',
          jsonEncode(validated.toJson()),
        );
      });

  Future<void> setSubject(
    String id,
    TextbookSubject subject, {
    required void Function() authorize,
  }) => _enqueue(() async {
    authorize();
    final current = find(id);
    if (current == null) throw const FormatException('教材已移除，请重新打开');
    final updated = Textbook.fromJson(current.withSubject(subject).toJson());
    await _box.put('$bookKeyPrefix$id', jsonEncode(updated.toJson()));
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

  /// 删除本书：移除书目登记与全部档案的阅读位置。
  ///
  /// 重复删除幂等；键不存在时无操作。书名/课程/学习进度的清理由调用方
  /// 编排（见缓存管理 sheet 的「删除本书」）。
  Future<void> delete(String id) => _enqueue(() async {
    await _box.delete('$bookKeyPrefix$id');
    for (final key in _box.keys.whereType<String>().toList()) {
      if (key.startsWith(readingKeyPrefix) && key.endsWith(':$id')) {
        await _box.delete(key);
      }
      if ((key.startsWith(recentKeyPrefix) ||
              key.startsWith(selectionKeyPrefix)) &&
          _box.get(key) == id) {
        await _box.delete(key);
      }
    }
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
