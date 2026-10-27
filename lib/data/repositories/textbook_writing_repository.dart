import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/domain/textbook_writing_review.dart';

/// 写一写进度仓库：与 [TextbookRecognitionRepository] 同构。
///
/// - 存储：`HiveBoxes.settings` 加密 box，键 `textbook_writing_v1:<digest>`
/// - 并发：`revision` 乐观校验 + `operationId` 幂等（最近 200 条）
/// - 失效：课程内容/审核/笔顺资产变化 → 字级指纹变化 → 旧记录丢弃
/// - 守卫：档案切换与数据恢复（`practice_draft_epoch`）后拒绝旧实例写入
class TextbookWritingRepository {
  TextbookWritingRepository({
    required this.book,
    required this.editionId,
    required this.courses,
    required this.hasStrokeData,
    Box<dynamic>? box,
  })  : profileId = ProfileScope.currentId,
        _profileRevision = ProfileScope.revision,
        _box = box ?? HiveBoxes.settings,
        epoch =
            HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0) as int;
  final Textbook book;
  final String editionId, profileId;
  final TextbookCourseRepository courses;

  /// 笔顺资产可用性查询；与指纹构建同源（design 2.4）。
  final bool Function(String character) hasStrokeData;
  final Box<dynamic> _box;
  final int epoch;
  final int _profileRevision;
  final _guard = PracticeDraftRepository();
  static final Map<String, Future<void>> _tails = {};
  String get key => 'textbook_writing_v1:${textbookTextDigest(
        jsonEncode([profileId, book.pdfSha256, editionId]),
      )}';

  void _current() {
    _guard.assertCurrent();
    if (ProfileScope.currentId != profileId ||
        ProfileScope.revision != _profileRevision) {
      throw StateError('档案已切换，请重新进入写一写');
    }
  }

  WritingProgress _read() {
    final raw = _box.get(key);
    final p = raw == null
        ? WritingProgress(
            profileId: profileId,
            bookId: book.pdfSha256,
            editionId: editionId,
          )
        : WritingProgress.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>,
          );
    if (p.profileId != profileId ||
        p.bookId != book.pdfSha256 ||
        p.editionId != editionId) {
      throw const FormatException('写字记录教材或档案不匹配');
    }
    return p;
  }

  /// 只保留与当前课程内容指纹一致的记录（内容/审核/资产变化即失效）。
  WritingProgress _currentContent(WritingProgress p, TextbookCoursePack pack) {
    final records = <String, WritingRecord>{};
    for (final lesson in pack.lessons) {
      for (final target in writingTargets(
        pack,
        lesson,
        hasStrokeData: hasStrokeData,
      )) {
        final k = WritingProgress.targetKey(lesson.id, target.id);
        final old = p.records[k];
        if (old?.fingerprint == target.fingerprint) records[k] = old!;
      }
    }
    return p.copy(records: records);
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

  Future<WritingProgress> load() => _serial(
        () => courses.withCurrentPack(book, (pack) async {
          _current();
          var p = _read();
          if (pack != null) p = _currentContent(p, pack);
          return p;
        }),
      );

  /// 一次写入：校验指纹与 revision 后施加 [reduce]。
  Future<WritingProgress> change({
    required String lessonId,
    required String fingerprint,
    required String operationId,
    required int expectedRevision,
    required WritingProgress Function(
      WritingProgress p,
      List<WritingTarget> targets,
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
          final targets = writingTargets(
            pack,
            lesson,
            hasStrokeData: hasStrokeData,
          );
          if (writingLessonFingerprint(targets) != fingerprint) {
            throw StateError('写字内容已更新，请重新进入写一写');
          }
          var p = _currentContent(_read(), pack);
          if (p.operations.contains(operationId)) return p;
          if (p.revision != expectedRevision) {
            throw StateError('学习记录已变化，请重新进入');
          }
          p = reduce(p, targets).copy(
            revision: p.revision + 1,
            operations: [...p.operations, operationId]
                .reversed
                .take(200)
                .toList()
                .reversed
                .toList(),
          );
          _current();
          await _box.put(key, jsonEncode(p.toJson()));
          return p;
        }),
      );

  /// 记录描红/自写阶段完成（事实计数，不影响复习日程）。
  Future<WritingProgress> recordStage({
    required String lessonId,
    required String fingerprint,
    required String targetId,
    required WritingStageDone stage,
    required String operationId,
    required int expectedRevision,
  }) =>
      change(
        lessonId: lessonId,
        fingerprint: fingerprint,
        operationId: operationId,
        expectedRevision: expectedRevision,
        reduce: (p, targets) {
          final k = WritingProgress.targetKey(lessonId, targetId);
          final target = targets.firstWhere((t) => t.id == targetId);
          final old = p.records[k] ??
              WritingRecord(fingerprint: target.fingerprint);
          return p.copy(
            records: {...p.records, k: writingRecordStage(old, stage)},
          );
        },
      );

  /// 记录一次几何比对结果（教练提示，不推进复习）。
  Future<WritingProgress> recordGeometryPass({
    required String lessonId,
    required String fingerprint,
    required String targetId,
    required bool passed,
    required String operationId,
    required int expectedRevision,
  }) =>
      change(
        lessonId: lessonId,
        fingerprint: fingerprint,
        operationId: operationId,
        expectedRevision: expectedRevision,
        reduce: (p, targets) {
          final k = WritingProgress.targetKey(lessonId, targetId);
          final target = targets.firstWhere((t) => t.id == targetId);
          final old = p.records[k] ??
              WritingRecord(fingerprint: target.fingerprint);
          return p.copy(
            records: {
              ...p.records,
              k: old.copy(
                geometryPasses: old.geometryPasses + (passed ? 1 : 0),
              ),
            },
          );
        },
      );

  /// 家长终审：唯一权威判定，同时推进间隔复习。
  Future<WritingProgress> recordParentConfirm({
    required String lessonId,
    required String fingerprint,
    required String targetId,
    required bool passed,
    required String day,
    required String operationId,
    required int expectedRevision,
  }) =>
      change(
        lessonId: lessonId,
        fingerprint: fingerprint,
        operationId: operationId,
        expectedRevision: expectedRevision,
        reduce: (p, targets) {
          final k = WritingProgress.targetKey(lessonId, targetId);
          final target = targets.firstWhere((t) => t.id == targetId);
          final old = p.records[k] ??
              WritingRecord(fingerprint: target.fingerprint);
          return p.copy(
            records: {
              ...p.records,
              k: writingRecordParentConfirm(old, passed: passed, day: day),
            },
          );
        },
      );
}