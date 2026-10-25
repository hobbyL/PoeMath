import 'package:poemath/data/models/textbook_course.dart';

/// 仅修改可审核内容，禁止借编辑目标更换原书身份、节点ID或所属关系。
TextbookCoursePack editTextbookCourseNode(
  TextbookCoursePack pack,
  String nodeId,
  Map<String, dynamic> changes,
) {
  final node = pack.nodes.where((node) => node.id == nodeId).firstOrNull;
  if (node == null) throw const FormatException('未找到待修改内容');
  final fields = <String>{
    'sources',
    if (node is TextbookCourseEdition) ...[
      'title',
      'publisher',
      'editionLabel',
      'editionNotes',
      'publicationDate',
      'editionNumber',
      'printingDate',
      'printingNumber',
      'sourceUrl',
    ],
    if (node is TextbookCourseUnit) 'title',
    if (node is TextbookCourseLesson) ...['title', 'kind', 'lessonNumber'],
    if (node is TextbookCourseParagraph) ...['text', 'pinyin'],
    if (node is TextbookCourseVocabulary) 'requirement',
    if (node is TextbookCourseRecitation) ...['instruction', 'ranges'],
    if (node is TextbookCourseExercise) ...[
      'prompt',
      'promptLayout',
      'origin',
      'answerType',
      'answers',
      'answerOrigin',
      'answerSources',
    ],
  };
  if (changes.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('不能修改原书身份、目标编号或所属关系');
  }
  final output = pack.toJson();
  final selected = _findNode(output, nodeId)!;
  final before = textbookContentDigest(selected);
  selected.addAll(changes);
  if (node is TextbookCourseExercise &&
      changes.containsKey('prompt') &&
      changes['prompt'] != node.prompt &&
      !changes.containsKey('promptLayout')) {
    // 编辑纯文字后，旧排版及其加点位置不再是新题目的可靠依据。
    selected.remove('promptLayout');
  }
  if (before == textbookContentDigest(selected)) return pack;
  selected['review'] = newTextbookReview();
  if (node is TextbookCourseParagraph && node is! TextbookCourseVocabulary) {
    final newText = selected['text'];
    if (newText is! String) throw const FormatException('正文须为文字');
    final runes = newText.runes.toList();
    for (final lesson in pack.lessons) {
      for (final recitation in lesson.recitations) {
        if (!recitation.ranges.any((range) => range.paragraphId == nodeId)) {
          continue;
        }
        final target = _findNode(output, recitation.id)!;
        for (final raw in target['ranges'] as List<dynamic>) {
          final range = raw as Map<String, dynamic>;
          if (range['paragraphId'] != nodeId) continue;
          final start = range['start'] as int;
          final end = range['end'] as int;
          if (end > runes.length) {
            throw const FormatException('新正文短于已有背诵范围，请先缩小该范围后再修改正文');
          }
          range['textSha256'] = textbookTextDigest(
            String.fromCharCodes(runes.sublist(start, end)),
          );
        }
        target['review'] = newTextbookReview();
      }
    }
  }
  output['contentRevision'] = pack.contentRevision + 1;
  output['status'] = 'draft';
  output['review'] = newTextbookReview();
  return TextbookCoursePack.fromJson(output);
}

Map<String, dynamic> newTextbookReview() => {
      'status': 'unreviewed',
      'reviewer': null,
      'reviewedAt': null,
      'contentSha256': null,
      'checks': <String>[],
      'notes': null,
    };

Map<String, dynamic> reviewTextbookCourse({
  required Map<String, dynamic> input,
  required String nodeId,
  required String reviewer,
  required String decision,
  required List<String> checks,
  required String notes,
  DateTime? at,
}) {
  final pack = TextbookCoursePack.fromJson(input);
  if (reviewer.trim().isEmpty ||
      notes.trim().isEmpty ||
      !const ['approved', 'rejected'].contains(decision) ||
      checks.toSet().length != checks.length) {
    throw const FormatException('须填写审核人、决定、核对说明和不重复的核对项');
  }
  final output = pack.toJson();
  Map<String, dynamic> selected;
  List<String> required;
  String? nodeDigest;
  if (nodeId == '@pack') {
    selected = output;
    required = ['coverage', 'content'];
    if (decision == 'approved') {
      final contentIssues = pack.publicationIssues
          .where(
            (issue) =>
                issue.path != r'$.status' &&
                issue.path != r'$.review' &&
                !issue.path.startsWith(r'$.permissions.'),
          )
          .toList();
      if (contentIssues.isNotEmpty) {
        throw FormatException(contentIssues.join('\n'));
      }
      output['status'] = 'reviewed';
    } else {
      output['status'] = 'draft';
    }
  } else {
    final found = pack.nodes.where((node) => node.id == nodeId).toList();
    if (found.length != 1) throw const FormatException('未找到唯一待审核节点');
    required = found.single.requiredChecks;
    nodeDigest = found.single.contentDigest;
    selected = _findNode(output, nodeId)!;
    if (decision == 'approved' && found.single.sources.isEmpty) {
      throw const FormatException('须先补齐原书页码依据');
    }
    // 节点审核变更后，必须重新作整包审核，避免保留先前的发布声明。
    output['status'] = 'draft';
    output['review'] = newTextbookReview();
  }
  if (decision == 'approved' && !required.every(checks.contains)) {
    throw FormatException('该节点须核对：${required.join(', ')}');
  }
  selected['review'] = {
    'status': decision,
    'reviewer': reviewer.trim(),
    'reviewedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
    'contentSha256': nodeDigest ?? textbookContentDigest(selected),
    'checks': checks,
    'notes': notes,
  };
  return TextbookCoursePack.fromJson(output).toJson();
}

Map<String, dynamic>? _findNode(Object? value, String id) {
  if (value is Map<String, dynamic>) {
    if (value['id'] == id) return value;
    for (final child in value.values) {
      final result = _findNode(child, id);
      if (result != null) return result;
    }
  } else if (value is List) {
    for (final child in value) {
      final result = _findNode(child, id);
      if (result != null) return result;
    }
  }
  return null;
}

/// 覆盖范围由审核者对照原书明确选择，不从空数组推断无要求。
TextbookCoursePack updateTextbookCourseCoverage(
  TextbookCoursePack pack,
  String lessonId,
  Map<String, TextbookCoverage> coverage,
) {
  final output = pack.toJson();
  final lesson = pack.lessons.where((node) => node.id == lessonId).firstOrNull;
  if (lesson == null ||
      coverage.length != TextbookCoursePack.categories.length ||
      !TextbookCoursePack.categories.every(coverage.containsKey)) {
    throw const FormatException('请选择本课全部类别的覆盖状态');
  }
  if (coverage.entries
      .every((entry) => lesson.coverage[entry.key] == entry.value)) {
    return pack;
  }
  final selected = _findNode(output, lessonId)!;
  selected['coverage'] = {
    for (final entry in coverage.entries) entry.key: entry.value.name,
  };
  selected['review'] = newTextbookReview();
  output['contentRevision'] = pack.contentRevision + 1;
  output['status'] = 'draft';
  output['review'] = newTextbookReview();
  return TextbookCoursePack.fromJson(output);
}
