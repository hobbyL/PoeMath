import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_course_review.dart';

/// 本机审核草稿独立于可重建的 PDF 缓存，不进入学习数据或云备份。
class TextbookCourseRepository {
  TextbookCourseRepository({Future<Directory> Function()? directoryProvider})
      : _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  static const maxBytes = 16 * 1024 * 1024;
  final Future<Directory> Function() _directoryProvider;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<File> _file(Textbook book) async {
    if (!Textbook.isValidId(book.pdfSha256)) {
      throw const FormatException('教材身份无效');
    }
    return File(
      '${(await _directoryProvider()).path}/textbooks/courses/${book.pdfSha256}.json',
    );
  }

  void _match(Textbook book, TextbookCoursePack pack) {
    final edition = pack.edition;
    if (edition.pdfSha256 != book.pdfSha256 ||
        edition.pageCount != book.pageCount ||
        edition.fileSize != book.fileSize ||
        edition.grade != book.grade ||
        edition.semester != book.semester) {
      throw const FormatException('草稿与当前教材的原书、册次或文件版本不匹配');
    }
  }

  /// 流式限制输入大小；导入文件与持久文件走同一严格解码器。
  Future<Map<String, dynamic>> _readJson(String path) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead()) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('课程草稿超过 16 MB，请按册整理后重试');
      }
      bytes.add(chunk);
    }
    final raw = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('请选择结构化课程 JSON 草稿');
    }
    return raw;
  }

  Future<TextbookCoursePack> readDraft(Textbook book, String path) async {
    final pack = TextbookCoursePack.fromJson(await _readJson(path));
    _match(book, pack);
    return pack;
  }

  Future<TextbookCourseDocument?> _loadDocument(Textbook book) async {
    final file = await _file(book);
    if (!await file.exists()) return null;
    final document =
        TextbookCourseDocument.fromJson(await _readJson(file.path));
    _match(book, document.pack);
    return document;
  }

  Future<TextbookCoursePack?> load(Textbook book) =>
      _serial(() async => (await _loadDocument(book))?.pack);
  Future<TextbookCourseDocument?> loadDocument(Textbook book) =>
      _serial(() => _loadDocument(book));

  /// 与审核写入共用排序；callback 不得再次调用本仓库的 load/save。
  Future<T> withCurrentPack<T>(
    Textbook book,
    Future<T> Function(TextbookCoursePack? pack) action,
  ) =>
      _serial(() async => action((await _loadDocument(book))?.pack));

  /// 只有用户明确确认导入时才替换；失败保留此前可用草稿。
  Future<void> importDraft(Textbook book, TextbookCoursePack pack) =>
      _serial(() => _writeDocument(book, TextbookCourseDocument(pack)));

  /// 防止另一审核页或重新导入后，旧页面把新数据覆盖掉。
  Future<void> save(
    Textbook book,
    TextbookCoursePack pack, {
    required TextbookCoursePack previous,
    void Function()? authorize,
  }) =>
      _serial(() async {
        authorize?.call();
        final document = await _loadDocument(book);
        final current = document?.pack;
        if (current == null ||
            jsonEncode(current.toJson()) != jsonEncode(previous.toJson())) {
          throw const FormatException('审核内容已更新，请返回并重新打开后再保存');
        }
        final generation = document!.generation;
        final remaining = pack.nodes.map((n) => n.id).toSet();
        final removed = <String>{
          ...?generation?.removed,
          ...current.nodes
              .map((n) => n.id)
              .where((id) => !remaining.contains(id)),
          for (final lesson in current.lessons)
            for (final category in [
              'recognitionCharacters',
              'writingCharacters',
              'words',
            ])
              for (final node in lesson.toJson()[category] as List)
                if (!remaining.contains((node as Map)['id']))
                  'vocabulary:${lesson.id}:$category:${textbookTextDigest(node['text'] as String)}',
        };
        authorize?.call();
        await _writeDocument(
          book,
          TextbookCourseDocument(
            pack,
            generation?.copyWith(removed: removed.toList()),
          ),
        );
      });

  /// 开始新一轮时只补课目；既有人工内容保留，其基线保持未知。
  Future<TextbookCourseDocument> beginGeneration(
    Textbook book,
    TextbookCourseDocument seed, {
    required void Function() check,
    bool restart = false,
  }) =>
      _serial(() async {
        check();
        final current = await _loadDocument(book);
        check();
        if (!restart &&
            current?.generation != null &&
            current!.generation!.phase != 'ready') {
          return current;
        }
        var document = seed;
        if (current != null) {
          final raw = current.pack.toJson();
          final lessons = raw['lessons'] as List;
          final units = raw['units'] as List;
          final seedLessons = seed.pack.toJson()['lessons'] as List;
          final seedUnits = seed.pack.toJson()['units'] as List;
          for (final value in seedUnits) {
            final unit = value as Map<String, dynamic>;
            if (!units.any((u) => (u as Map)['id'] == unit['id'])) {
              units.add(unit);
            }
          }
          for (final value in seedLessons) {
            final lesson = value as Map<String, dynamic>;
            if (!lessons.any((l) => (l as Map)['id'] == lesson['id'])) {
              lessons.add(lesson);
              final unit =
                  units.firstWhere((u) => (u as Map)['id'] == lesson['unitId'])
                      as Map;
              if (!(unit['lessonIds'] as List).contains(lesson['id'])) {
                (unit['lessonIds'] as List).add(lesson['id']);
              }
            }
          }
          final baselines = <String, String>{
            for (final value in seedLessons)
              if (!current.pack.lessons
                  .any((l) => l.id == (value as Map)['id']))
                (value as Map)['id'] as String:
                    textbookDraftBaseline(value as Map<String, dynamic>),
            ...?current.generation?.baselines,
          };
          if (jsonEncode(raw) != jsonEncode(current.pack.toJson())) {
            _invalidate(raw);
          }
          document = TextbookCourseDocument(
            TextbookCoursePack.fromJson(raw),
            seed.generation!.copyWith(
              plans: [
                for (final plan in seed.generation!.plans)
                  current.generation?.plans
                          .where((p) => p.id == plan.id && p.edited)
                          .firstOrNull ??
                      plan,
              ],
              baselines: baselines,
              removed: current.generation?.removed ?? [],
            ),
          );
        }
        await _writeDocument(book, document, check: check);
        return document;
      });

  /// 在串行队列内读取最新版本，逐课提交；从不使用任务开始时的整包快照覆盖。
  Future<TextbookCourseDocument> commitGeneratedLesson(
    Textbook book,
    String runId,
    Map<String, dynamic> lesson,
    List<TextbookDraftCandidate> candidates, {
    required void Function() check,
  }) =>
      _serial(() async {
        check();
        final document = await _loadDocument(book);
        check();
        if (document?.generation?.runId != runId) {
          throw const FormatException('课程草稿已替换，请重新打开');
        }
        final generation = document!.generation!;
        final id = lesson['id'] as String;
        final raw = document.pack.toJson();
        final lessons = raw['lessons'] as List;
        final index = lessons.indexWhere((l) => (l as Map)['id'] == id);
        if (index < 0) throw const FormatException('生成课目已移除');
        final current = lessons[index] as Map<String, dynamic>;
        // 删除目标的墓碑在重试与升级后仍生效。
        final proposed = jsonDecode(jsonEncode(lesson)) as Map<String, dynamic>;
        for (final category in TextbookCoursePack.categories) {
          (proposed[category] as List).removeWhere(
            (n) =>
                generation.removed.contains((n as Map)['id']) ||
                n['text'] is String &&
                    generation.removed.contains(
                      'vocabulary:$id:$category:${textbookTextDigest(n['text'] as String)}',
                    ),
          );
        }
        final existing = document.pack.lessons.firstWhere((l) => l.id == id);
        final untouched =
            generation.baselines[id] == textbookDraftBaseline(current) &&
                existing.review.status == TextbookReviewStatus.unreviewed &&
                existing.targets.every(
                  (n) => n.review.status == TextbookReviewStatus.unreviewed,
                ) &&
                existing.coverage.values
                    .every((c) => c == TextbookCoverage.pending);
        final pending = {...generation.pending};
        final baselines = {...generation.baselines};
        if (untouched) {
          if (jsonEncode(current) != jsonEncode(proposed)) {
            lessons[index] = proposed;
            _invalidate(raw);
          }
          baselines[id] = textbookDraftBaseline(proposed);
          pending.remove(id);
        } else if (jsonEncode(current) != jsonEncode(proposed)) {
          pending[id] = proposed;
        }
        final updated = generation.copyWith(
          completed: {...generation.completed, id}.toList(),
          baselines: baselines,
          candidates: {
            ...generation.candidates,
            id: candidates
                .where((c) => !generation.removed.contains('candidate:${c.id}'))
                .toList(),
          },
          pending: pending,
          errors: {...generation.errors}..remove(id),
        );
        final result =
            TextbookCourseDocument(TextbookCoursePack.fromJson(raw), updated);
        await _writeDocument(book, result, check: check);
        return result;
      });

  Future<TextbookCourseDocument?> updateGeneration(
    Textbook book,
    String runId,
    TextbookDraftManifest Function(TextbookDraftManifest) update, {
    void Function()? check,
  }) =>
      _serial(() async {
        check?.call();
        final document = await _loadDocument(book);
        check?.call();
        if (document?.generation?.runId != runId) return document;
        final result = TextbookCourseDocument(
          document!.pack,
          update(document.generation!),
        );
        await _writeDocument(book, result, check: check);
        return result;
      });

  Future<void> resolveDifference(
    Textbook book,
    String lessonId, {
    required bool accept,
    required TextbookCoursePack previous,
  }) =>
      _serial(() async {
        final document = await _loadDocument(book);
        if (document == null ||
            jsonEncode(document.pack.toJson()) !=
                jsonEncode(previous.toJson())) {
          throw const FormatException('审核内容已更新，请返回并重新打开后再保存');
        }
        final generation = document.generation;
        final replacement = generation?.pending[lessonId];
        if (generation == null || replacement == null) return;
        final raw = document.pack.toJson();
        if (accept) {
          final lessons = raw['lessons'] as List;
          lessons[lessons.indexWhere((l) => (l as Map)['id'] == lessonId)] =
              replacement;
          _invalidate(raw);
        }
        await _writeDocument(
          book,
          TextbookCourseDocument(
            TextbookCoursePack.fromJson(raw),
            generation.copyWith(
              pending: {...generation.pending}..remove(lessonId),
              baselines: {
                ...generation.baselines,
                if (accept) lessonId: textbookDraftBaseline(replacement),
              },
            ),
          ),
        );
      });

  void _invalidate(Map<String, dynamic> raw) {
    raw['status'] = 'draft';
    raw['review'] = newTextbookReview();
    raw['coverage'] = 'partial';
    raw['contentRevision'] = (raw['contentRevision'] as int) + 1;
  }

  Future<void> _writeDocument(
    Textbook book,
    TextbookCourseDocument document, {
    void Function()? check,
  }) async {
    final pack = document.pack;
    _match(book, pack);
    // 不信任调用方对象，重新经过唯一课程解码器。
    final encoded = utf8.encode(
      jsonEncode(TextbookCourseDocument.fromJson(document.toJson()).toJson()),
    );
    if (encoded.length > maxBytes) throw const FormatException('课程草稿超过 16 MB');
    final file = await _file(book);
    check?.call();
    await file.parent.create(recursive: true);
    if (document.generation != null && await file.exists()) {
      final backup = File('${file.path}.v1.bak');
      final old = await _readJson(file.path);
      if (!old.containsKey('storageVersion') && !await backup.exists()) {
        await file.copy(backup.path);
      }
    }
    final temporary = await file.parent.createTemp('.course-');
    try {
      final pending = File('${temporary.path}/draft.json');
      await pending.writeAsBytes(encoded, flush: true);
      check?.call();
      await pending.rename(file.path);
    } finally {
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException catch (error) {
        // rename 后的清理失败不能将已完成的保存报告为失败。
        AppLogger.e('课程临时文件清理失败', tag: 'TextbookCourse', error: error);
      }
    }
  }
}
