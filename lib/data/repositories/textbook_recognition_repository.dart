import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';

class TextbookRecognitionRepository {
  TextbookRecognitionRepository({
    required this.book,
    required this.editionId,
    required this.courses,
    Box<dynamic>? box,
  })  : profileId = ProfileScope.currentId,
        _profileRevision = ProfileScope.revision,
        _box = box ?? HiveBoxes.settings,
        epoch =
            HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0) as int;
  final Textbook book;
  final String editionId, profileId;
  final TextbookCourseRepository courses;
  final Box<dynamic> _box;
  final int epoch;
  final int _profileRevision;
  final _guard = PracticeDraftRepository();
  static final Map<String, Future<void>> _tails = {};
  String get key => 'textbook_recognition_v1:${textbookTextDigest(
        jsonEncode([
          profileId,
          book.pdfSha256,
          editionId,
        ]),
      )}';
  void _current() {
    _guard.assertCurrent();
    if (ProfileScope.currentId != profileId ||
        ProfileScope.revision != _profileRevision) {
      throw StateError('档案已切换，请重新进入认一认');
    }
  }

  RecognitionProgress _read() {
    final raw = _box.get(key);
    final p = raw == null
        ? RecognitionProgress(
            profileId: profileId,
            bookId: book.pdfSha256,
            editionId: editionId,
          )
        : RecognitionProgress.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>,
          );
    if (p.profileId != profileId ||
        p.bookId != book.pdfSha256 ||
        p.editionId != editionId) {
      throw const FormatException('认字记录教材或档案不匹配');
    }
    return p;
  }

  void _validateSession(RecognitionSession s, List<RecognitionTarget> targets) {
    for (final q in s.questions) {
      final target =
          targets.where((t) => t.id == q.targetId && t.ready).firstOrNull;
      if (target == null) throw const FormatException('认字题目目标损坏');
      if (q.kind == RecognitionQuestionKind.listen ||
          q.kind == RecognitionQuestionKind.context) {
        final cue = target.cues.where((c) => c.key == q.cueKey).firstOrNull;
        if (cue == null) throw const FormatException('认字题目示范损坏');
        if (q.kind == RecognitionQuestionKind.listen) {
          if (q.options.length < 2 ||
              q.options.length > 4 ||
              q.options.toSet().length != q.options.length ||
              q.options.where((id) => id == target.id).length != 1 ||
              q.options
                  .any((id) => !targets.any((t) => t.id == id && t.ready))) {
            throw const FormatException('认字选项损坏');
          }
        } else {
          final context = q.options.length == 1
              ? target.cues
                  .where(
                    (c) => c.key == q.options.single && c.nodeId != target.id,
                  )
                  .firstOrNull
              : null;
          if (context == null ||
              jsonEncode(q.positions) != jsonEncode(context.positions)) {
            throw const FormatException('认字词句位置损坏');
          }
        }
      }
    }
  }

  RecognitionProgress _currentContent(
      RecognitionProgress p, TextbookCoursePack pack,) {
    final records = <String, RecognitionRecord>{};
    final audio = <String, RecognitionAudioApproval>{};
    for (final lesson in pack.lessons) {
      for (final target in recognitionTargets(pack, lesson)) {
        final key = RecognitionProgress.targetKey(lesson.id, target.id);
        final old = p.records[key];
        if (old?.fingerprint == target.fingerprint) records[key] = old!;
        for (final cue in target.cues) {
          final approval = p.audio[cue.key];
          if (approval?.fingerprint == target.fingerprint) {
            audio[cue.key] = approval!;
          }
        }
      }
    }
    return p.copy(records: records, audio: audio);
  }

  Future<T> _serial<T>(Future<T> Function() action) => _guard.guard(() async {
        final previous = _tails[key];
        final work = () async {
          if (previous != null) {
            try {
              await previous;
            } on Object {/* 后续重试不受失败影响。 */}
          }
          _current();
          return action();
        }();
        final tail =
            work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
        _tails[key] = tail;
        try {
          return await work;
        } finally {
          if (identical(_tails[key], tail)) _tails.remove(key);
        }
      });
  Future<RecognitionProgress> load() => _serial(
        () => courses.withCurrentPack(book, (pack) async {
          _current();
          var p = _read();
          if (pack != null) p = _currentContent(p, pack);
          final s = p.session;
          if (s != null) {
            final lesson =
                pack?.lessons.where((l) => l.id == s.lessonId).firstOrNull;
            if (s.epoch != epoch ||
                lesson == null ||
                recognitionLessonFingerprint(
                      recognitionTargets(pack!, lesson),
                    ) !=
                    s.fingerprint) {
              p = p.copy(clearSession: true);
            } else {
              _validateSession(s, recognitionTargets(pack, lesson));
            }
          }
          return p;
        }),
      );

  Future<RecognitionProgress> change({
    required String lessonId,
    required String fingerprint,
    required String operationId,
    required int expectedRevision,
    String? sessionId,
    void Function()? authorize,
    required RecognitionProgress Function(
      RecognitionProgress p,
      List<RecognitionTarget> targets,
    ) reduce,
  }) =>
      _serial(
        () => courses.withCurrentPack(book, (pack) async {
          _current();
          if (pack == null || pack.edition.id != editionId) {
            throw StateError('教材内容已更新，请重新进入');
          }
          final lesson =
              pack.lessons.where((l) => l.id == lessonId).firstOrNull;
          if (lesson == null) throw StateError('课目已更新，请重新进入');
          final targets = recognitionTargets(pack, lesson);
          if (recognitionLessonFingerprint(targets) != fingerprint) {
            throw StateError('生字或审核已更新，请重新准备');
          }
          var p = _currentContent(_read(), pack);
          if (p.operations.contains(operationId)) return p;
          if (p.revision != expectedRevision) {
            throw StateError('学习记录已变化，请重新进入');
          }
          if (sessionId != null &&
              (p.session?.id != sessionId ||
                  p.session?.epoch != epoch ||
                  p.session?.fingerprint != fingerprint)) {
            throw StateError('原轮次已失效，请重新进入');
          }
          authorize?.call();
          p = reduce(p, targets).copy(
            revision: p.revision + 1,
            operations: [...p.operations, operationId]
                .reversed
                .take(200)
                .toList()
                .reversed
                .toList(),
          );
          if (p.session case final s?) {
            if (s.lessonId == lessonId &&
                s.fingerprint == fingerprint &&
                s.epoch == epoch) {
              _validateSession(s, targets);
            }
          }
          _current();
          authorize?.call();
          await _box.put(key, jsonEncode(p.toJson()));
          return p;
        }),
      );
}
