import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;

part 'math_textbook_expression.dart';
part 'math_textbook_learning.dart';
part 'math_textbook_course_outline.dart';

/// 数学课程与语文课程使用独立格式；来源与审核均绑定实际 PDF。
class MathTextbookRegion {
  const MathTextbookRegion({
    required this.page,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.printedPage,
  });

  final int page;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final String? printedPage;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  MathTextbookRegion merge(MathTextbookRegion other) {
    if (page != other.page) throw const FormatException('不同原书页不能合成一个区域');
    return MathTextbookRegion(
      page: page,
      left: left < other.left ? left : other.left,
      top: top < other.top ? top : other.top,
      right: right > other.right ? right : other.right,
      bottom: bottom > other.bottom ? bottom : other.bottom,
      printedPage: printedPage ?? other.printedPage,
    );
  }

  bool containsCenter(MathTextbookRegion other) =>
      page == other.page &&
      left <= other.centerX &&
      other.centerX <= right &&
      top <= other.centerY &&
      other.centerY <= bottom;

  Map<String, dynamic> toJson() => {
    'page': page,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    if (printedPage != null) 'printedPage': printedPage,
  };

  factory MathTextbookRegion.fromJson(Object? value) {
    final raw = _object(value, '原书区域');
    final coords = ['left', 'top', 'right', 'bottom'].map((key) {
      final value = raw[key];
      if (value is! num || !value.isFinite || value < 0 || value > 1) {
        throw const FormatException('原书区域须为 0～1 的有限坐标');
      }
      return value.toDouble();
    }).toList();
    if (coords[2] <= coords[0] || coords[3] <= coords[1]) {
      throw const FormatException('原书区域不能为空或倒置');
    }
    return MathTextbookRegion(
      page: _integer(raw['page'], '原书页', min: 1, max: 10000),
      left: coords[0],
      top: coords[1],
      right: coords[2],
      bottom: coords[3],
      printedPage: raw['printedPage'] == null
          ? null
          : _string(raw['printedPage'], '印刷页', max: 40),
    );
  }
}

class MathTextbookSpan {
  const MathTextbookSpan.text(String value) : text = value, expression = null;
  const MathTextbookSpan.math(MathTextbookExpression value)
    : expression = value,
      text = null;
  final String? text;
  final MathTextbookExpression? expression;
  String get readable => text ?? expression!.readable;
  Map<String, dynamic> toJson() => text != null
      ? {'kind': 'text', 'text': text}
      : {'kind': 'math', 'expression': expression!.toJson()};
  factory MathTextbookSpan.fromJson(Object? value) {
    final raw = _object(value, '文字与公式片段');
    return switch (raw['kind']) {
      'text' => MathTextbookSpan.text(
        _string(raw['text'], '文字', max: 20000, empty: true),
      ),
      'math' => MathTextbookSpan.math(
        MathTextbookExpression.fromJson(raw['expression']),
      ),
      _ => throw const FormatException('不支持的数学内容片段'),
    };
  }
}

enum MathTextbookBlockKind { text, formula, illustration, exercise, sourcePage }

class MathTextbookBlock {
  MathTextbookBlock({
    required this.id,
    required this.kind,
    required List<MathTextbookSpan> spans,
    required List<MathTextbookRegion> sources,
    List<String> warnings = const [],
    this.exerciseNumber,
    this.parentNote = '',
  }) : spans = List.unmodifiable(spans),
       sources = List.unmodifiable(sources),
       warnings = List.unmodifiable(warnings);

  final String id;
  final MathTextbookBlockKind kind;
  final List<MathTextbookSpan> spans;
  final List<MathTextbookRegion> sources;
  final List<String> warnings;
  final String? exerciseNumber;
  final String parentNote;
  String get text => spans.map((span) => span.readable).join();
  bool get needsSource =>
      warnings.isNotEmpty ||
      kind == MathTextbookBlockKind.illustration ||
      kind == MathTextbookBlockKind.sourcePage;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'spans': spans.map((s) => s.toJson()).toList(),
    'sources': sources.map((s) => s.toJson()).toList(),
    'warnings': warnings,
    if (exerciseNumber != null) 'exerciseNumber': exerciseNumber,
    'parentNote': parentNote,
  };

  factory MathTextbookBlock.fromJson(Object? value) {
    final raw = _object(value, '数学内容块');
    final kind = MathTextbookBlockKind.values
        .where((k) => k.name == raw['kind'])
        .firstOrNull;
    if (kind == null) throw const FormatException('数学内容块类型无效');
    final sources = _list(
      raw['sources'],
      '来源区域',
      max: 40,
    ).map(MathTextbookRegion.fromJson).toList();
    if (sources.isEmpty) throw const FormatException('数学内容必须保留来源区域');
    final spans = _list(
      raw['spans'],
      '内容片段',
      max: 1000,
    ).map(MathTextbookSpan.fromJson).toList();
    if (!spans.any((s) => s.expression != null || s.text!.trim().isNotEmpty) &&
        kind != MathTextbookBlockKind.illustration &&
        kind != MathTextbookBlockKind.sourcePage) {
      throw const FormatException('文字或公式内容不能为空');
    }
    return MathTextbookBlock(
      id: _identifier(raw['id']),
      kind: kind,
      spans: spans,
      sources: sources,
      warnings: _list(
        raw['warnings'],
        '待核原因',
        max: 30,
      ).map((v) => _string(v, '待核原因', max: 500)).toList(),
      exerciseNumber: raw['exerciseNumber'] == null
          ? null
          : _string(raw['exerciseNumber'], '题号', max: 40),
      parentNote: _string(raw['parentNote'], '家长说明', empty: true, max: 5000),
    );
  }
}

class MathTextbookReview {
  const MathTextbookReview({
    required this.contentDigest,
    required this.reviewer,
    required this.reviewedAt,
    required this.editingMilliseconds,
  });
  final String contentDigest;
  final String reviewer;
  final DateTime reviewedAt;

  /// 本次打开编辑页的前台停留时间，排除生成、后台、保存与原书浏览。
  /// 不累计历次编辑，也不能直接视为实际人工补齐成本。
  final int editingMilliseconds;
  Map<String, dynamic> toJson() => {
    'contentDigest': contentDigest,
    'reviewer': reviewer,
    'reviewedAt': reviewedAt.toUtc().toIso8601String(),
    'editingMilliseconds': editingMilliseconds,
  };
  factory MathTextbookReview.fromJson(Object? value) {
    final raw = _object(value, '数学审核');
    final at = DateTime.tryParse(_string(raw['reviewedAt'], '审核时间', max: 40));
    if (at == null) throw const FormatException('数学审核时间无效');
    return MathTextbookReview(
      contentDigest: _hash(raw['contentDigest']),
      reviewer: _string(raw['reviewer'], '审核人', max: 100),
      reviewedAt: at,
      editingMilliseconds: _integer(
        raw['editingMilliseconds'],
        '编辑时间',
        max: 31536000000,
      ),
    );
  }
}

class MathTextbookLesson {
  MathTextbookLesson({
    required this.id,
    required this.title,
    required this.startPage,
    required this.endPage,
    required List<MathTextbookBlock> blocks,
    this.review,
    this.learning,
  }) : blocks = List.unmodifiable(blocks);
  final String id;
  final String title;
  final int startPage;
  final int endPage;
  final List<MathTextbookBlock> blocks;
  final MathTextbookReview? review;
  final MathTextbookLearning? learning;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startPage': startPage,
    'endPage': endPage,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (learning != null) 'learning': learning!.toJson(),
    if (review != null) 'review': review!.toJson(),
  };

  String contentDigest(String pdfSha256) => textbookContentDigest({
    'subject': 'math',
    'pdfSha256': pdfSha256,
    'lesson': toJson(),
  });
  bool isApproved(String pdfSha256) =>
      review != null && review!.contentDigest == contentDigest(pdfSha256);

  MathTextbookLesson edit({
    String? title,
    List<MathTextbookBlock>? blocks,
    MathTextbookLearning? learning,
  }) => MathTextbookLesson(
    id: id,
    title: title ?? this.title,
    startPage: startPage,
    endPage: endPage,
    blocks: blocks ?? this.blocks,
    learning: learning ?? this.learning,
  );

  MathTextbookLesson approve({
    required String pdfSha256,
    required String reviewer,
    required int editingMilliseconds,
    DateTime? at,
  }) {
    final reviewed = MathTextbookLesson(
      id: id,
      title: title,
      startPage: startPage,
      endPage: endPage,
      blocks: blocks,
      learning: learning,
      review: MathTextbookReview(
        contentDigest: contentDigest(pdfSha256),
        reviewer: reviewer,
        reviewedAt: at ?? DateTime.now(),
        editingMilliseconds: editingMilliseconds,
      ),
    );
    return MathTextbookLesson.fromJson(reviewed.toJson());
  }

  factory MathTextbookLesson.fromJson(Object? value) {
    final raw = _object(value, '数学课时');
    final start = _integer(raw['startPage'], '起始页', min: 1, max: 10000);
    final end = _integer(raw['endPage'], '结束页', min: start, max: 10000);
    if (end - start >= 40) throw const FormatException('请每次整理不超过 40 页的课时');
    final blocks = _list(
      raw['blocks'],
      '数学内容',
      max: 4000,
    ).map(MathTextbookBlock.fromJson).toList();
    if (blocks.isEmpty ||
        blocks.map((b) => b.id).toSet().length != blocks.length) {
      throw const FormatException('课时内容为空或编号重复');
    }
    final sourcePages = <int>{};
    for (final block in blocks) {
      for (final source in block.sources) {
        if (source.page < start || source.page > end) {
          throw const FormatException('内容来源超出本课页范围');
        }
        sourcePages.add(source.page);
      }
    }
    if (sourcePages.length != end - start + 1) {
      throw const FormatException('课时遗漏了原书页面，请保留缺失页供核对');
    }
    final learning = raw['learning'] == null
        ? null
        : MathTextbookLearning.fromJson(raw['learning']);
    learning?.matchBlocks(blocks);
    return MathTextbookLesson(
      id: _identifier(raw['id']),
      title: _string(raw['title'], '课时名称', max: 200),
      startPage: start,
      endPage: end,
      blocks: blocks,
      learning: learning,
      review: raw['review'] == null
          ? null
          : MathTextbookReview.fromJson(raw['review']),
    );
  }
}

class MathTextbookCourse {
  MathTextbookCourse({
    required this.pdfSha256,
    required this.pageCount,
    required this.fileSize,
    required this.grade,
    required this.semester,
    this.revision = 0,
    List<MathTextbookLesson> lessons = const [],
    List<MathTextbookLesson> pendingLessons = const [],
    this.outline,
  }) : lessons = List.unmodifiable(lessons),
       pendingLessons = List.unmodifiable(pendingLessons);

  factory MathTextbookCourse.forBook(Textbook book) => MathTextbookCourse(
    pdfSha256: book.pdfSha256,
    pageCount: book.pageCount,
    fileSize: book.fileSize,
    grade: book.grade,
    semester: book.semester,
  );

  final String pdfSha256;
  final int pageCount;
  final int fileSize;
  final int grade;
  final String semester;
  final int revision;
  final List<MathTextbookLesson> lessons;
  final List<MathTextbookLesson> pendingLessons;
  final MathTextbookCourseOutline? outline;

  Map<String, dynamic> toJson() => {
    'kind': 'mathTextbookCourse',
    'schemaVersion': 2,
    'subject': 'math',
    'pdfSha256': pdfSha256,
    'pageCount': pageCount,
    'fileSize': fileSize,
    'grade': grade,
    'semester': semester,
    'revision': revision,
    'lessons': lessons.map((l) => l.toJson()).toList(),
    'pendingLessons': pendingLessons.map((l) => l.toJson()).toList(),
    if (outline != null) 'outline': outline!.toJson(),
  };

  MathTextbookCourse replace({
    List<MathTextbookLesson>? lessons,
    List<MathTextbookLesson>? pendingLessons,
    MathTextbookCourseOutline? outline,
  }) => MathTextbookCourse.fromJson({
    ...toJson(),
    'revision': revision + 1,
    if (lessons != null) 'lessons': lessons.map((l) => l.toJson()).toList(),
    if (pendingLessons != null)
      'pendingLessons': pendingLessons.map((l) => l.toJson()).toList(),
    if (outline != null) 'outline': outline.toJson(),
  });

  void matchBook(Textbook book) {
    if (book.subject != TextbookSubject.math ||
        book.pdfSha256 != pdfSha256 ||
        book.pageCount != pageCount ||
        book.fileSize != fileSize ||
        book.grade != grade ||
        book.semester != semester) {
      throw const FormatException('数学课程与当前原书不匹配');
    }
  }

  factory MathTextbookCourse.fromJson(Object? value) {
    final raw = _object(value, '数学课程');
    if (raw['kind'] != 'mathTextbookCourse' ||
        !const [1, 2].contains(raw['schemaVersion']) ||
        raw['subject'] != 'math') {
      throw const FormatException('不支持的数学课程格式');
    }
    final pageCount = _integer(raw['pageCount'], '总页数', min: 1, max: 10000);
    final lessons = _list(
      raw['lessons'],
      '课时列表',
      max: 1000,
    ).map(MathTextbookLesson.fromJson).toList();
    final pending = _list(
      raw['pendingLessons'],
      '待采纳版本',
      max: 1000,
    ).map(MathTextbookLesson.fromJson).toList();
    for (final list in [lessons, pending]) {
      if (list.map((l) => l.id).toSet().length != list.length ||
          list.any((l) => l.endPage > pageCount)) {
        throw const FormatException('数学课时编号重复或超出原书页数');
      }
    }
    if (pending.any((p) => !lessons.any((l) => l.id == p.id))) {
      throw const FormatException('待采纳版本缺少对应课时');
    }
    final semester = _string(raw['semester'], '学期', max: 1);
    if (semester != '上' && semester != '下') throw const FormatException('学期无效');
    final outline = raw['outline'] == null
        ? null
        : MathTextbookCourseOutline.fromJson(raw['outline']);
    if (outline != null &&
        (outline.ranges.any((r) => r.endPage > pageCount) ||
            outline.directoryPages.any((p) => p > pageCount))) {
      throw const FormatException('整理目录超出本书页数');
    }
    if (outline?.completedLessonIds?.any((id) {
          final range = outline.ranges.firstWhere(
            (range) => range.lessonId == id,
          );
          return !lessons.any(
            (lesson) =>
                lesson.id == id &&
                lesson.startPage == range.startPage &&
                lesson.endPage == range.endPage,
          );
        }) ==
        true) {
      throw const FormatException('已整理目录课时缺少对应范围的草稿');
    }
    return MathTextbookCourse(
      pdfSha256: _hash(raw['pdfSha256']),
      pageCount: pageCount,
      fileSize: _integer(raw['fileSize'], '文件大小', min: 1, max: 1073741824),
      grade: _integer(raw['grade'], '年级', min: 1, max: 6),
      semester: semester,
      revision: _integer(raw['revision'], '内容版本', max: 2147483647),
      lessons: lessons,
      pendingLessons: pending,
      outline: outline,
    );
  }
}

Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map<String, dynamic>) throw FormatException('$label须为对象');
  return value;
}

List<dynamic> _list(Object? value, String label, {required int max}) {
  if (value is! List || value.length > max) {
    throw FormatException('$label列表无效或过长');
  }
  return value;
}

String _string(
  Object? value,
  String label, {
  required int max,
  bool empty = false,
}) {
  if (value is! String ||
      value.length > max ||
      (!empty && value.trim().isEmpty)) {
    throw FormatException('$label文字无效或过长');
  }
  return value;
}

int _integer(Object? value, String label, {int min = 0, required int max}) {
  if (value is! int || value < min || value > max) {
    throw FormatException('$label数值无效');
  }
  return value;
}

String _hash(Object? value) {
  if (value is! String || !Textbook.isValidId(value)) {
    throw const FormatException('原书或内容摘要无效');
  }
  return value;
}

String _identifier(Object? value) {
  final id = _string(value, '内容编号', max: 160);
  if (!RegExp(r'^[a-zA-Z0-9:_-]+$').hasMatch(id)) {
    throw const FormatException('内容编号无效');
  }
  return id;
}
