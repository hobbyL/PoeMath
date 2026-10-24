import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';

/// 新增、删除和重排也走严格解码器；相关范围必须重新核对。
TextbookCoursePack addTextbookCourseTarget(
  TextbookCoursePack pack,
  String lessonId,
  String category, {
  required String id,
  required String text,
  List<int>? pages,
}) {
  if (!TextbookCoursePack.categories.contains(category)) {
    throw const FormatException('内容类别无效');
  }
  final raw = pack.toJson();
  final lesson = _lesson(raw, lessonId);
  final sources = pages == null
      ? lesson['sources']
      : [
          for (final p in pages)
            {
              'pdfPage': p,
              'printedPage': null,
              'extractionStatus': 'text_extracted',
            },
        ];
  final node = <String, dynamic>{
    'id': id,
    'sources': sources,
    'review': newTextbookReview(),
  };
  if (category == 'recitations') {
    final paragraphs = lesson['paragraphs'] as List;
    if (paragraphs.isEmpty) throw const FormatException('请先添加课文段落，再选取背诵范围');
    final p = paragraphs.first as Map;
    node.addAll({
      'instruction': text,
      'ranges': [
        {
          'paragraphId': p['id'],
          'start': 0,
          'end': (p['text'] as String).runes.length,
          'textSha256': textbookTextDigest(p['text'] as String),
        }
      ],
    });
  } else if (category == 'exercises') {
    node.addAll({
      'prompt': text,
      'origin': 'textbook',
      'answerType': 'none',
      'answers': <String>[],
      'answerOrigin': 'none',
      'answerSources': <dynamic>[],
    });
  } else {
    node.addAll({
      'text': text,
      'pinyin': null,
      if (category != 'paragraphs')
        'requirement': category == 'words'
            ? 'reading'
            : category == 'writingCharacters'
                ? 'writing'
                : 'recognition',
    });
  }
  (lesson[category] as List).add(node);
  _changed(raw, lesson, category, pack.contentRevision);
  return TextbookCoursePack.fromJson(raw);
}

TextbookCoursePack removeTextbookCourseTarget(
  TextbookCoursePack pack,
  String id, {
  bool removeReferences = false,
}) {
  final raw = pack.toJson();
  for (final value in raw['lessons'] as List) {
    final lesson = value as Map<String, dynamic>;
    for (final category in TextbookCoursePack.categories) {
      final list = lesson[category] as List;
      if (!list.any((n) => (n as Map)['id'] == id)) continue;
      final recitations = lesson['recitations'] as List;
      final linked = recitations
          .where(
            (n) => ((n as Map)['ranges'] as List)
                .any((r) => (r as Map)['paragraphId'] == id),
          )
          .toList();
      if (linked.isNotEmpty && !removeReferences) {
        throw const FormatException('此段被背诵目标引用，请先调整范围或确认一并删除引用目标');
      }
      recitations.removeWhere(linked.contains);
      list.removeWhere((n) => (n as Map)['id'] == id);
      _changed(raw, lesson, category, pack.contentRevision);
      if (linked.isNotEmpty) {
        (lesson['coverage'] as Map)['recitations'] = 'pending';
      }
      return TextbookCoursePack.fromJson(raw);
    }
  }
  throw const FormatException('未找到待删除内容');
}

TextbookCoursePack reorderTextbookParagraph(
  TextbookCoursePack pack,
  String lessonId,
  String id,
  int offset,
) {
  final raw = pack.toJson();
  final lesson = _lesson(raw, lessonId);
  final paragraphs = lesson['paragraphs'] as List;
  final index = paragraphs.indexWhere((p) => (p as Map)['id'] == id);
  if (index < 0 || index + offset < 0 || index + offset >= paragraphs.length) {
    return pack;
  }
  final paragraph = paragraphs.removeAt(index);
  paragraphs.insert(index + offset, paragraph);
  for (final r in lesson['recitations'] as List) {
    (r as Map)['review'] = newTextbookReview();
  }
  (lesson['coverage'] as Map)['recitations'] = 'pending';
  _changed(raw, lesson, 'paragraphs', pack.contentRevision);
  return TextbookCoursePack.fromJson(raw);
}

TextbookCoursePack splitTextbookParagraph(
  TextbookCoursePack pack,
  String lessonId,
  String id,
  int at,
  String newId,
) {
  final raw = pack.toJson();
  final lesson = _lesson(raw, lessonId);
  final paragraphs = lesson['paragraphs'] as List;
  final index = paragraphs.indexWhere((p) => (p as Map)['id'] == id);
  if (index < 0) throw const FormatException('未找到课文段落');
  _noReferences(lesson, {id});
  final p = paragraphs[index] as Map<String, dynamic>;
  final runes = (p['text'] as String).runes.toList();
  if (at < 1 || at >= runes.length) throw const FormatException('拆分位置须在段落中间');
  final second = <String, dynamic>{
    ...p,
    'id': newId,
    'text': String.fromCharCodes(runes.sublist(at)),
    'pinyin': null,
    'review': newTextbookReview(),
  };
  p['text'] = String.fromCharCodes(runes.sublist(0, at));
  p['pinyin'] = null;
  p['review'] = newTextbookReview();
  paragraphs.insert(index + 1, second);
  _changed(raw, lesson, 'paragraphs', pack.contentRevision);
  return TextbookCoursePack.fromJson(raw);
}

TextbookCoursePack mergeTextbookParagraph(
  TextbookCoursePack pack,
  String lessonId,
  String id,
) {
  final raw = pack.toJson();
  final lesson = _lesson(raw, lessonId);
  final paragraphs = lesson['paragraphs'] as List;
  final index = paragraphs.indexWhere((p) => (p as Map)['id'] == id);
  if (index < 0 || index + 1 >= paragraphs.length) {
    throw const FormatException('后面没有可合并的段落');
  }
  final p = paragraphs[index] as Map<String, dynamic>;
  final next = paragraphs[index + 1] as Map<String, dynamic>;
  _noReferences(lesson, {id, next['id'] as String});
  p['text'] = '${p['text']}\n${next['text']}';
  p['pinyin'] = null;
  p['review'] = newTextbookReview();
  p['sources'] = [
    ...(p['sources'] as List),
    ...(next['sources'] as List).where(
      (s) => !(p['sources'] as List)
          .any((old) => (old as Map)['pdfPage'] == (s as Map)['pdfPage']),
    ),
  ];
  paragraphs.removeAt(index + 1);
  _changed(raw, lesson, 'paragraphs', pack.contentRevision);
  return TextbookCoursePack.fromJson(raw);
}

void _noReferences(Map<String, dynamic> lesson, Set<String> ids) {
  if ((lesson['recitations'] as List).any(
    (r) => ((r as Map)['ranges'] as List)
        .any((p) => ids.contains((p as Map)['paragraphId'])),
  )) {
    throw const FormatException('请先调整此段的背诵范围，再拆分或合并段落');
  }
}

Map<String, dynamic> _lesson(Map<String, dynamic> raw, String id) {
  final lesson =
      (raw['lessons'] as List).where((l) => (l as Map)['id'] == id).firstOrNull;
  if (lesson == null) throw const FormatException('未找到课目');
  return lesson as Map<String, dynamic>;
}

void _changed(
  Map<String, dynamic> raw,
  Map<String, dynamic> lesson,
  String category,
  int revision,
) {
  (lesson['coverage'] as Map)[category] = 'pending';
  lesson['review'] = newTextbookReview();
  raw['review'] = newTextbookReview();
  raw['status'] = 'draft';
  raw['coverage'] = 'partial';
  raw['contentRevision'] = revision + 1;
  for (final u in raw['units'] as List) {
    if ((u as Map)['id'] == lesson['unitId']) u['review'] = newTextbookReview();
  }
}
