part of 'math_textbook_course.dart';

class MathTextbookCourseRange {
  const MathTextbookCourseRange({
    required this.title,
    required this.startPage,
    required this.endPage,
    this.unitTitle = '',
    this.needsAlignment = false,
  });
  final String title, unitTitle;
  final int startPage, endPage;
  final bool needsAlignment;
  String get lessonId => 'math-$startPage-$endPage';
  Map<String, dynamic> toJson() => {
    'title': title,
    'unitTitle': unitTitle,
    'startPage': startPage,
    'endPage': endPage,
    'needsAlignment': needsAlignment,
  };
  factory MathTextbookCourseRange.fromJson(Object? value) {
    final raw = _object(value, '目录课时区间');
    final start = _integer(raw['startPage'], '目录原书页', min: 1, max: 10000);
    final end = _integer(raw['endPage'], '目录结束页', min: start, max: 10000);
    if (end - start >= 40) throw const FormatException('目录课时区间不能超过 40 页');
    return MathTextbookCourseRange(
      title: _string(raw['title'], '目录标题', max: 200),
      startPage: start,
      endPage: end,
      unitTitle: _string(raw['unitTitle'] ?? '', '目录单元', max: 200, empty: true),
      needsAlignment: _boolean(raw['needsAlignment'] ?? false, '课时边界待核'),
    );
  }
}

class MathTextbookCourseOutline {
  MathTextbookCourseOutline({
    required this.source,
    required List<MathTextbookCourseRange> ranges,
    List<int> directoryPages = const [],
    List<String> warnings = const [],
    List<String>? completedLessonIds,
  }) : ranges = List.unmodifiable(ranges),
       directoryPages = List.unmodifiable(directoryPages),
       warnings = List.unmodifiable(warnings),
       completedLessonIds = completedLessonIds == null
           ? null
           : List.unmodifiable(completedLessonIds);
  final String source;
  final List<MathTextbookCourseRange> ranges;
  final List<int> directoryPages;
  final List<String> warnings;

  /// Null identifies older drafts; a new run explicitly records even zero saves.
  final List<String>? completedLessonIds;

  MathTextbookCourseOutline withCompleted(Iterable<String> ids) =>
      MathTextbookCourseOutline.fromJson({
        ...toJson(),
        'completedLessonIds': ids.toList(),
      });
  Map<String, dynamic> toJson() => {
    'source': source,
    'ranges': ranges.map((r) => r.toJson()).toList(),
    'directoryPages': directoryPages,
    'warnings': warnings,
    if (completedLessonIds != null) 'completedLessonIds': completedLessonIds,
  };
  factory MathTextbookCourseOutline.fromJson(Object? value) {
    final raw = _object(value, '本书整理目录');
    final source = _string(raw['source'], '目录来源', max: 20);
    if (!const ['bookmarks', 'text', 'pages'].contains(source)) {
      throw const FormatException('目录来源无效');
    }
    final ranges = _list(
      raw['ranges'],
      '目录课时',
      max: 400,
    ).map(MathTextbookCourseRange.fromJson).toList();
    if (ranges.isEmpty) throw const FormatException('本书整理目录缺少区间');
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].startPage <= ranges[i - 1].endPage) {
        throw const FormatException('目录区间重复或倒置');
      }
    }
    final completed = raw['completedLessonIds'] == null
        ? null
        : _strings(raw['completedLessonIds'], '已整理课时', 400, 200);
    if (completed != null &&
        (completed.toSet().length != completed.length ||
            completed.any((id) => !ranges.any((r) => r.lessonId == id)))) {
      throw const FormatException('已整理课时与目录不符');
    }
    return MathTextbookCourseOutline(
      source: source,
      ranges: ranges,
      directoryPages: _list(
        raw['directoryPages'] ?? [],
        '目录页',
        max: 100,
      ).map((p) => _integer(p, '目录页', min: 1, max: 10000)).toList(),
      warnings: _strings(raw['warnings'] ?? [], '目录待核说明', 30, 1000),
      completedLessonIds: completed,
    );
  }
}
