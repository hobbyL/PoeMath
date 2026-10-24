import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 课程包与 PDF 书目、自动目录独立；未审草稿不能成为学习内容。
enum TextbookReviewStatus { unreviewed, approved, rejected }

enum TextbookCoverage { pending, notApplicable, complete }

enum TextbookAnswerType { none, exact, reference, parentCheck }

class TextbookCourseIssue {
  const TextbookCourseIssue(this.path, this.code, this.message);
  final String path;
  final String code;
  final String message;
  Map<String, Object?> toJson() => {
        'path': path,
        'code': code,
        'message': message,
      };
  @override
  String toString() => '$path [$code] $message';
}

class TextbookSourcePage {
  const TextbookSourcePage(
    this.pdfPage,
    this.printedPage,
    this.extractionStatus,
  );
  final int pdfPage;
  final String extractionStatus;

  /// 印刷页可含罗马数字或附录编号；未知时为 null，不推断统一偏移。
  final String? printedPage;
}

class TextbookContentReview {
  const TextbookContentReview({
    required this.status,
    required this.checks,
    this.reviewer,
    this.reviewedAt,
    this.contentSha256,
    this.notes,
  });
  final TextbookReviewStatus status;
  final List<String> checks;
  final String? reviewer;
  final DateTime? reviewedAt;
  final String? contentSha256;
  final String? notes;

  bool approves(Map<String, dynamic> value, Iterable<String> requiredChecks) =>
      status == TextbookReviewStatus.approved &&
      contentSha256 == textbookContentDigest(value) &&
      requiredChecks.every(checks.contains);
}

/// 审核绑定内容而非布尔值。子节点审核元数据变化不改正文摘要；正文变化会失效。
String textbookContentDigest(Map<String, dynamic> value) {
  Object? canonical(Object? input) {
    if (input is Map<String, dynamic>) {
      final keys = input.keys.where((key) => key != 'review').toList()..sort();
      return {for (final key in keys) key: canonical(input[key])};
    }
    if (input is List) return input.map(canonical).toList();
    return input;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(value)))).toString();
}

String textbookTextDigest(String text) =>
    sha256.convert(utf8.encode(text)).toString();

bool _isHan(int rune) =>
    rune == 0x3007 ||
    (rune >= 0x3400 && rune <= 0x4dbf) ||
    (rune >= 0x4e00 && rune <= 0x9fff) ||
    (rune >= 0xf900 && rune <= 0xfaff) ||
    (rune >= 0x20000 && rune <= 0x323af);

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class TextbookCourseNode {
  TextbookCourseNode._(
    this.id,
    this.path,
    this.sources,
    this.review,
    this._json,
  );
  final String id;
  final String path;
  final List<TextbookSourcePage> sources;
  final TextbookContentReview review;
  final Map<String, dynamic> _json;
  late final Map<String, dynamic> _editionBinding;
  Map<String, dynamic> toJson() => _copy(_json);

  List<String> get requiredChecks => const ['sourcePages', 'content'];
  Map<String, dynamic> get _reviewPayload =>
      {'editionBinding': _editionBinding, 'node': _json};
  String get contentDigest => textbookContentDigest(_reviewPayload);
  bool get isApproved => review.approves(_reviewPayload, requiredChecks);
}

class TextbookCourseEdition extends TextbookCourseNode {
  TextbookCourseEdition._(
    super.id,
    super.path,
    super.sources,
    super.review,
    super.json,
    this.pdfSha256,
    this.pageCount,
    this.fileSize,
    this.title,
    this.grade,
    this.semester,
    this.publisher,
    this.editionLabel,
  ) : super._();
  final String pdfSha256;
  final int pageCount;
  final int fileSize;
  final String title;
  final int grade;
  final String semester;
  final String publisher;
  final String editionLabel;
  String? get publicationDate => _json['publicationDate'] as String?;
  String? get printingDate => _json['printingDate'] as String?;
  int? get editionNumber => _json['editionNumber'] as int?;
  int? get printingNumber => _json['printingNumber'] as int?;
  @override
  List<String> get requiredChecks => const ['sourcePages', 'edition'];
}

class TextbookCourseUnit extends TextbookCourseNode {
  TextbookCourseUnit._(
    super.id,
    super.path,
    super.sources,
    super.review,
    super.json,
    this.title,
    this.lessonIds,
  ) : super._();
  final String title;
  final List<String> lessonIds;
}

class TextbookCourseParagraph extends TextbookCourseNode {
  TextbookCourseParagraph._(
    super.id,
    super.path,
    super.sources,
    super.review,
    super.json,
    this.text,
    this.pinyin,
  ) : super._();
  final String text;

  /// 每个非空白 Unicode 码点一个 token，标点也须占位；null 表示未提供。
  final List<String>? pinyin;
  @override
  List<String> get requiredChecks => [
        ...super.requiredChecks,
        if (text.runes.any(_isHan)) 'pinyin',
      ];
}

class TextbookCourseVocabulary extends TextbookCourseParagraph {
  TextbookCourseVocabulary._(
    super.id,
    super.path,
    super.sources,
    super.review,
    super.json,
    super.text,
    super.pinyin,
  ) : super._();

  /// reading 仅为课内词语；原书明确要求才可标为 dictation。
  String get requirement => _json['requirement'] as String;
  @override
  List<String> get requiredChecks => [...super.requiredChecks, 'requirement'];
}

class TextbookRecitationRange {
  const TextbookRecitationRange(
    this.paragraphId,
    this.start,
    this.end,
    this.textSha256,
  );
  final String paragraphId;
  final String textSha256;

  /// 原始段落 Unicode 码点的半开区间 [start, end)，包含空白字符。
  final int start;
  final int end;
}

class TextbookCourseRecitation extends TextbookCourseNode {
  TextbookCourseRecitation._(
    super.id,
    super.path,
    super.sources,
    super.review,
    super.json,
    this.instruction,
    this.ranges,
  ) : super._();
  final String instruction;
  final List<TextbookRecitationRange> ranges;
  @override
  List<String> get requiredChecks => const ['sourcePages', 'content', 'range'];
}

class TextbookCourseExercise extends TextbookCourseNode {
  TextbookCourseExercise._(
    super.id,
    super.path,
    super.sources,
    super.review,
    super.json,
    this.prompt,
    this.answerType,
    this.answers,
    this.answerOrigin,
    this.answerSources,
  ) : super._();
  final String prompt;
  final TextbookAnswerType answerType;
  final List<String> answers;

  /// textbook / reviewerReference / none，参考要点不当作唯一标准答案。
  final String answerOrigin;
  final List<TextbookSourcePage> answerSources;
  @override
  List<String> get requiredChecks => [
        ...super.requiredChecks,
        'answer',
      ];
}

class TextbookCourseLesson extends TextbookCourseNode {
  TextbookCourseLesson._(
    super.id,
    super.path,
    super.sources,
    super.review,
    super.json,
    this.unitId,
    this.title,
    this.kind,
    this.lessonNumber,
    this.coverage,
    this.paragraphs,
    this.recognitionCharacters,
    this.writingCharacters,
    this.words,
    this.recitations,
    this.exercises,
  ) : super._();
  final String unitId;
  final String title;
  final String kind;
  final int? lessonNumber;
  final Map<String, TextbookCoverage> coverage;
  final List<TextbookCourseParagraph> paragraphs;
  final List<TextbookCourseVocabulary> recognitionCharacters;
  final List<TextbookCourseVocabulary> writingCharacters;
  final List<TextbookCourseVocabulary> words;
  final List<TextbookCourseRecitation> recitations;
  final List<TextbookCourseExercise> exercises;
  @override
  List<String> get requiredChecks =>
      const ['sourcePages', 'content', 'coverage'];

  Iterable<TextbookCourseNode> get targets sync* {
    yield* paragraphs;
    yield* recognitionCharacters;
    yield* writingCharacters;
    yield* words;
    yield* recitations;
    yield* exercises;
  }

  bool covers(String category) =>
      coverage[category] == TextbookCoverage.complete;
}

/// 唯一课程 JSON 解码/引用校验入口，开发工具与后续 Flutter 消费共用。
class TextbookCoursePack {
  TextbookCoursePack._(
    this._json,
    this.edition,
    this.units,
    this.lessons,
    this.review,
  );
  static const schemaVersion = 1;
  static const categories = [
    'paragraphs',
    'recognitionCharacters',
    'writingCharacters',
    'words',
    'recitations',
    'exercises',
  ];
  final Map<String, dynamic> _json;
  final TextbookCourseEdition edition;
  final List<TextbookCourseUnit> units;
  final List<TextbookCourseLesson> lessons;
  final TextbookContentReview review;
  int get contentRevision => _json['contentRevision'] as int;
  String get status => _json['status'] as String;
  String get coverage => _json['coverage'] as String;
  int? get expectedLessonCount => _json['expectedLessonCount'] as int?;
  Map<String, dynamic> toJson() => _copy(_json);
  String targetKey(String id) => '${edition.id}/$id';
  Iterable<TextbookCourseNode> get nodes sync* {
    yield edition;
    yield* units;
    for (final lesson in lessons) {
      yield lesson;
      yield* lesson.targets;
    }
  }

  /// 草稿的语法合法与可发布是两个结果；许可未知和未审数据均保留为阻断项。
  List<TextbookCourseIssue> get publicationIssues {
    final issues = <TextbookCourseIssue>[];
    void add(String path, String code, String message) =>
        issues.add(TextbookCourseIssue(path, code, message));
    if (status != 'reviewed') add(r'$.status', 'draft', '课程包仍为草稿');
    if (!review.approves(_json, const ['coverage', 'content'])) {
      add(r'$.review', 'review', '整包未审、审核过期或缺少核对项');
    }
    final permissions = _json['permissions'] as Map<String, dynamic>;
    for (final key in ['content', 'applicationUse']) {
      final permission = permissions[key] as Map<String, dynamic>;
      if (permission['status'] != 'permitted' ||
          (permission['evidence'] as String).trim().isEmpty) {
        add(r'$.permissions.' + key, 'permission', '许可尚未确认或缺少依据');
      }
    }
    if (lessons.isEmpty ||
        !lessons.any((lesson) => lesson.targets.isNotEmpty)) {
      add(r'$.lessons', 'empty', '课程包没有学习内容');
    }
    if (coverage == 'complete' &&
        (expectedLessonCount == null ||
            expectedLessonCount != lessons.length)) {
      add(r'$.expectedLessonCount', 'coverage', '完整覆盖须核对预期课目数');
    }
    for (final node in nodes) {
      if (node.sources.isEmpty) add(node.path, 'source', '缺少原书页码依据');
      if (!node.isApproved) {
        add('${node.path}.review', 'review', '未审、审核过期或缺少核对项');
      }
      if (node is TextbookCourseVocabulary && node.pinyin == null) {
        add(node.path, 'pinyin', '字词目标缺少人工核对的注音');
      }
      if (node is TextbookCourseLesson) {
        for (final entry in node.coverage.entries) {
          if (entry.value == TextbookCoverage.pending) {
            add('${node.path}.coverage.${entry.key}', 'coverage', '该课此类目标尚未核对');
          }
        }
      }
    }
    return List.unmodifiable(issues);
  }

  bool get isPublishable => publicationIssues.isEmpty;

  factory TextbookCoursePack.fromJson(Map<String, dynamic> input) =>
      _CourseDecoder(_copy(input)).decode();

  factory TextbookCoursePack.forPublication(Map<String, dynamic> input) {
    final pack = TextbookCoursePack.fromJson(input);
    final issues = pack.publicationIssues;
    if (issues.isNotEmpty) throw FormatException(issues.join('\n'));
    return pack;
  }
}

class _CourseDecoder {
  _CourseDecoder(this.json);
  final Map<String, dynamic> json;
  final ids = <String>{};
  late int pageCount;

  Never fail(String path, String message) =>
      throw FormatException('$path: $message');
  Map<String, dynamic> object(Object? value, String path) {
    if (value is! Map<String, dynamic>) fail(path, '须为对象');
    return value;
  }

  List<Object?> list(Object? value, String path) {
    if (value is! List) fail(path, '须为数组');
    return value;
  }

  String string(Object? value, String path, {bool empty = false}) {
    if (value is! String || (!empty && value.trim().isEmpty)) {
      fail(path, '须为非空字符串');
    }
    return value;
  }

  int integer(Object? value, String path, {int min = 1, int? max}) {
    if (value is! int || value < min || (max != null && value > max)) {
      fail(path, '整数超出范围');
    }
    return value;
  }

  String choice(Object? value, String path, List<String> choices) {
    final result = string(value, path);
    if (!choices.contains(result)) fail(path, '未知值 $result');
    return result;
  }

  void fields(Map<String, dynamic> value, String path, List<String> names) {
    final unknown = value.keys.where((key) => !names.contains(key));
    if (unknown.isNotEmpty) fail(path, '未知字段 ${unknown.join(', ')}');
    for (final name in names) {
      if (!value.containsKey(name)) fail('$path.$name', '缺少字段（未知信息请显式填 null）');
    }
  }

  String id(Object? value, String path) {
    final result = string(value, path);
    if (!RegExp(r'^[a-z][a-z0-9._-]{0,127}$').hasMatch(result) ||
        !ids.add(result)) {
      fail(path, 'ID无效或重复');
    }
    return result;
  }

  List<String> strings(Object? value, String path) => List.unmodifiable([
        for (final (index, item) in list(value, path).indexed)
          string(item, '$path[$index]'),
      ]);
  List<TextbookSourcePage> sources(Object? value, String path) =>
      List.unmodifiable([
        for (final (index, item) in list(value, path).indexed)
          source(object(item, '$path[$index]'), '$path[$index]'),
      ]);
  TextbookSourcePage source(Map<String, dynamic> value, String path) {
    fields(value, path, ['pdfPage', 'printedPage', 'extractionStatus']);
    final page = integer(value['pdfPage'], '$path.pdfPage', max: pageCount);
    final printed = value['printedPage'];
    return TextbookSourcePage(
      page,
      printed == null ? null : string(printed, '$path.printedPage'),
      choice(value['extractionStatus'], '$path.extractionStatus', [
        'text_extracted',
        'no_text',
        'low_text',
        'replacement_characters',
        'cid_placeholders',
        'extraction_error',
        'manual',
      ]),
    );
  }

  TextbookContentReview review(Object? value, String path) {
    final raw = object(value, path);
    fields(raw, path, [
      'status',
      'reviewer',
      'reviewedAt',
      'contentSha256',
      'checks',
      'notes',
    ]);
    final status = TextbookReviewStatus.values.byName(
      choice(
        raw['status'],
        '$path.status',
        TextbookReviewStatus.values.map((e) => e.name).toList(),
      ),
    );
    final reviewer = raw['reviewer'] == null
        ? null
        : string(raw['reviewer'], '$path.reviewer');
    DateTime? at;
    if (raw['reviewedAt'] != null) {
      final timestamp = string(raw['reviewedAt'], '$path.reviewedAt');
      at = DateTime.tryParse(timestamp);
      if (at == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp)) {
        fail(path, '审核时间须含时区');
      }
    }
    final hash = raw['contentSha256'];
    if (hash != null &&
        (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))) {
      fail(path, '审核摘要无效');
    }
    final checks = strings(raw['checks'], '$path.checks');
    if (checks.toSet().length != checks.length) fail(path, '核对项重复');
    if (status != TextbookReviewStatus.unreviewed &&
        (reviewer == null || at == null || hash == null)) {
      fail(path, '审核决定须记录审核人、时间和内容摘要');
    }
    return TextbookContentReview(
      status: status,
      checks: checks,
      reviewer: reviewer,
      reviewedAt: at,
      contentSha256: hash as String?,
      notes: raw['notes'] == null
          ? null
          : string(raw['notes'], '$path.notes', empty: true),
    );
  }

  List<String>? pinyin(Map<String, dynamic> value, String path, String text) {
    if (value['pinyin'] == null) return null;
    final tokens = strings(value['pinyin'], '$path.pinyin');
    final characters = text.runes
        .map(String.fromCharCode)
        .where((c) => c.trim().isNotEmpty)
        .toList();
    if (tokens.length != characters.length) {
      fail('$path.pinyin', '注音须与非空白Unicode字符逐字对齐（含标点）');
    }
    for (var i = 0; i < characters.length; i++) {
      if (_isHan(characters[i].runes.single) &&
          !RegExp(r'^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿê]+[1-5]?$')
              .hasMatch(tokens[i])) {
        fail('$path.pinyin[$i]', '汉字注音须为小写拼音，不能使用抽取损坏的字形编码');
      }
      if (RegExp(r'^[\p{P}\p{S}]$', unicode: true).hasMatch(characters[i]) &&
          tokens[i] != characters[i]) {
        fail('$path.pinyin[$i]', '标点占位必须与原文一致');
      }
    }
    return tokens;
  }

  TextbookCoursePack decode() {
    const p = r'$';
    fields(json, p, [
      'schemaVersion',
      'kind',
      'status',
      'contentRevision',
      'coverage',
      'expectedLessonCount',
      'edition',
      'permissions',
      'review',
      'units',
      'lessons',
    ]);
    if (json['schemaVersion'] is! int ||
        json['schemaVersion'] != TextbookCoursePack.schemaVersion ||
        json['kind'] != 'textbookCourse') {
      fail(p, '课程包版本或类型不支持');
    }
    choice(json['status'], '$p.status', ['draft', 'reviewed']);
    integer(json['contentRevision'], '$p.contentRevision');
    choice(json['coverage'], '$p.coverage', ['partial', 'complete']);
    if (json['expectedLessonCount'] != null) {
      integer(json['expectedLessonCount'], '$p.expectedLessonCount');
    }
    final e = object(json['edition'], '$p.edition');
    fields(e, '$p.edition', [
      'id',
      'pdfSha256',
      'pageCount',
      'fileSize',
      'title',
      'grade',
      'semester',
      'publisher',
      'editionLabel',
      'editionNotes',
      'publicationDate',
      'editionNumber',
      'printingDate',
      'printingNumber',
      'sourceUrl',
      'sources',
      'review',
    ]);
    pageCount = integer(e['pageCount'], '$p.edition.pageCount', max: 5000);
    final hash = string(e['pdfSha256'], '$p.edition.pdfSha256');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      fail('$p.edition.pdfSha256', 'PDF SHA-256无效');
    }
    final url = string(e['sourceUrl'], '$p.edition.sourceUrl');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      fail('$p.edition.sourceUrl', '须为HTTPS来源');
    }
    string(e['editionNotes'], '$p.edition.editionNotes', empty: true);
    for (final key in ['publicationDate', 'printingDate']) {
      if (e[key] != null &&
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$')
              .hasMatch(string(e[key], '$p.edition.$key'))) {
        fail('$p.edition.$key', '须为YYYY-MM，未知时为null');
      }
    }
    for (final key in ['editionNumber', 'printingNumber']) {
      if (e[key] != null) integer(e[key], '$p.edition.$key');
    }
    final edition = TextbookCourseEdition._(
      id(e['id'], '$p.edition.id'),
      '$p.edition',
      sources(e['sources'], '$p.edition.sources'),
      review(e['review'], '$p.edition.review'),
      e,
      hash,
      pageCount,
      integer(e['fileSize'], '$p.edition.fileSize'),
      string(e['title'], '$p.edition.title'),
      integer(e['grade'], '$p.edition.grade', max: 6),
      choice(e['semester'], '$p.edition.semester', ['上', '下']),
      string(e['publisher'], '$p.edition.publisher'),
      string(e['editionLabel'], '$p.edition.editionLabel'),
    );
    final permission = object(json['permissions'], '$p.permissions');
    fields(permission, '$p.permissions', ['content', 'applicationUse']);
    for (final key in permission.keys) {
      final entry = object(permission[key], '$p.permissions.$key');
      fields(entry, '$p.permissions.$key', ['status', 'evidence']);
      choice(
        entry['status'],
        '$p.permissions.$key.status',
        ['unknown', 'permitted', 'prohibited'],
      );
      string(entry['evidence'], '$p.permissions.$key.evidence', empty: true);
    }
    final units = <TextbookCourseUnit>[];
    for (final (index, raw) in list(json['units'], '$p.units').indexed) {
      final path = '$p.units[$index]';
      final unit = object(raw, path);
      fields(unit, path, ['id', 'title', 'sources', 'review', 'lessonIds']);
      units.add(
        TextbookCourseUnit._(
          id(unit['id'], '$path.id'),
          path,
          sources(unit['sources'], '$path.sources'),
          review(unit['review'], '$path.review'),
          unit,
          string(unit['title'], '$path.title'),
          strings(unit['lessonIds'], '$path.lessonIds'),
        ),
      );
    }
    final lessons = <TextbookCourseLesson>[];
    for (final (index, raw) in list(json['lessons'], '$p.lessons').indexed) {
      lessons
          .add(lesson(object(raw, '$p.lessons[$index]'), '$p.lessons[$index]'));
    }
    final lessonMap = {for (final lesson in lessons) lesson.id: lesson};
    final assigned = <String>{};
    for (final unit in units) {
      for (final lessonId in unit.lessonIds) {
        if (!assigned.add(lessonId) || lessonMap[lessonId]?.unitId != unit.id) {
          fail(unit.path, '课目引用不存在、重复或所属单元不一致');
        }
      }
    }
    if (assigned.length != lessons.length) fail('$p.lessons', '存在未归属单元的课目');
    final pack = TextbookCoursePack._(
      json,
      edition,
      List.unmodifiable(units),
      List.unmodifiable(lessons),
      review(json['review'], '$p.review'),
    );
    final binding = Map<String, dynamic>.unmodifiable({
      'editionId': edition.id,
      'pdfSha256': edition.pdfSha256,
      'pageCount': edition.pageCount,
      'fileSize': edition.fileSize,
    });
    for (final node in pack.nodes) {
      node._editionBinding = binding;
    }
    return pack;
  }

  TextbookCourseParagraph paragraph(
    Map<String, dynamic> raw,
    String path, {
    bool vocabulary = false,
    bool single = false,
  }) {
    fields(raw, path, [
      'id',
      'text',
      'pinyin',
      'sources',
      'review',
      if (vocabulary) 'requirement',
    ]);
    final text = string(raw['text'], '$path.text');
    if (single && (text.runes.length != 1 || !_isHan(text.runes.single))) {
      fail('$path.text', '认字/写字目标须为单个Unicode字符');
    }
    if (vocabulary) {
      choice(
        raw['requirement'],
        '$path.requirement',
        ['recognition', 'writing', 'reading', 'dictation'],
      );
    }
    final tokens = pinyin(raw, path, text);
    final key = id(raw['id'], '$path.id');
    final pages = sources(raw['sources'], '$path.sources');
    final reviewed = review(raw['review'], '$path.review');
    return vocabulary
        ? TextbookCourseVocabulary._(
            key,
            path,
            pages,
            reviewed,
            raw,
            text,
            tokens,
          )
        : TextbookCourseParagraph._(
            key,
            path,
            pages,
            reviewed,
            raw,
            text,
            tokens,
          );
  }

  TextbookCourseLesson lesson(Map<String, dynamic> raw, String path) {
    fields(raw, path, [
      'id',
      'unitId',
      'title',
      'kind',
      'lessonNumber',
      'sources',
      'review',
      'coverage',
      ...TextbookCoursePack.categories,
    ]);
    final key = id(raw['id'], '$path.id');
    final unitId = string(raw['unitId'], '$path.unitId');
    final title = string(raw['title'], '$path.title');
    final kind = choice(raw['kind'], '$path.kind', [
      'text',
      'literacy',
      'poetry',
      'classical',
      'oral',
      'writing',
      'garden',
      'reading',
      'appendix',
      'other',
    ]);
    final number = raw['lessonNumber'] == null
        ? null
        : integer(raw['lessonNumber'], '$path.lessonNumber');
    final pages = sources(raw['sources'], '$path.sources');
    final reviewed = review(raw['review'], '$path.review');
    final coverageRaw = object(raw['coverage'], '$path.coverage');
    fields(coverageRaw, '$path.coverage', TextbookCoursePack.categories);
    final coverage = <String, TextbookCoverage>{};
    for (final category in TextbookCoursePack.categories) {
      final state = TextbookCoverage.values.byName(
        choice(
          coverageRaw[category],
          '$path.coverage.$category',
          TextbookCoverage.values.map((e) => e.name).toList(),
        ),
      );
      final entries = list(raw[category], '$path.$category');
      if ((state == TextbookCoverage.notApplicable && entries.isNotEmpty) ||
          (state == TextbookCoverage.complete && entries.isEmpty)) {
        fail('$path.coverage.$category', '覆盖状态与目标数量不一致');
      }
      coverage[category] = state;
    }
    List<TextbookCourseParagraph> paragraphs(
      String category, {
      bool vocabulary = false,
      bool single = false,
    }) =>
        List.unmodifiable([
          for (final (i, value)
              in list(raw[category], '$path.$category').indexed)
            paragraph(
              object(value, '$path.$category[$i]'),
              '$path.$category[$i]',
              vocabulary: vocabulary,
              single: single,
            ),
        ]);
    final text = paragraphs('paragraphs');
    final recognition =
        paragraphs('recognitionCharacters', vocabulary: true, single: true)
            .cast<TextbookCourseVocabulary>();
    final writing =
        paragraphs('writingCharacters', vocabulary: true, single: true)
            .cast<TextbookCourseVocabulary>();
    final words =
        paragraphs('words', vocabulary: true).cast<TextbookCourseVocabulary>();
    for (final node in [...recognition, ...writing, ...words]) {
      final allowed = recognition.contains(node)
          ? ['recognition']
          : writing.contains(node)
              ? ['writing']
              : ['reading', 'dictation'];
      if (!allowed.contains(node.requirement)) {
        fail(node.path, '字词目标类别与原书要求不一致');
      }
    }
    final byId = {for (final p in text) p.id: p};
    final recitations = <TextbookCourseRecitation>[];
    for (final (i, value)
        in list(raw['recitations'], '$path.recitations').indexed) {
      final p = '$path.recitations[$i]';
      final recite = object(value, p);
      fields(recite, p, ['id', 'instruction', 'ranges', 'sources', 'review']);
      final ranges = <TextbookRecitationRange>[];
      for (final (j, value) in list(recite['ranges'], '$p.ranges').indexed) {
        final rp = '$p.ranges[$j]';
        final range = object(value, rp);
        fields(range, rp, ['paragraphId', 'start', 'end', 'textSha256']);
        final paragraphId = string(range['paragraphId'], '$rp.paragraphId');
        final paragraph = byId[paragraphId];
        if (paragraph == null) fail(rp, '背诵范围必须引用本课段落');
        final start = integer(
          range['start'],
          '$rp.start',
          min: 0,
          max: paragraph.text.runes.length - 1,
        );
        final end = integer(
          range['end'],
          '$rp.end',
          min: start + 1,
          max: paragraph.text.runes.length,
        );
        if (ranges.any(
          (r) => r.paragraphId == paragraphId && start < r.end && end > r.start,
        )) {
          fail(rp, '背诵范围重叠');
        }
        final textHash = string(range['textSha256'], '$rp.textSha256');
        final rangeText = String.fromCharCodes(
          paragraph.text.runes.toList().sublist(start, end),
        );
        if (textHash != textbookTextDigest(rangeText)) {
          fail(rp, '背诵范围文字摘要不匹配，须重新核对目标');
        }
        ranges.add(TextbookRecitationRange(paragraphId, start, end, textHash));
      }
      if (ranges.isEmpty) fail(p, '背诵目标须有明确范围');
      recitations.add(
        TextbookCourseRecitation._(
          id(recite['id'], '$p.id'),
          p,
          sources(recite['sources'], '$p.sources'),
          review(recite['review'], '$p.review'),
          recite,
          string(recite['instruction'], '$p.instruction'),
          List.unmodifiable(ranges),
        ),
      );
    }
    final exercises = <TextbookCourseExercise>[];
    for (final (i, value)
        in list(raw['exercises'], '$path.exercises').indexed) {
      final p = '$path.exercises[$i]';
      final exercise = object(value, p);
      fields(exercise, p, [
        'id',
        'prompt',
        'origin',
        'answerType',
        'answers',
        'answerOrigin',
        'answerSources',
        'sources',
        'review',
      ]);
      choice(exercise['origin'], '$p.origin', ['textbook', 'curated']);
      final type = TextbookAnswerType.values.byName(
        choice(
          exercise['answerType'],
          '$p.answerType',
          TextbookAnswerType.values.map((e) => e.name).toList(),
        ),
      );
      final answers = strings(exercise['answers'], '$p.answers');
      final origin = choice(
        exercise['answerOrigin'],
        '$p.answerOrigin',
        ['none', 'textbook', 'reviewerReference'],
      );
      final answerPages =
          sources(exercise['answerSources'], '$p.answerSources');
      if ((type == TextbookAnswerType.exact ||
              type == TextbookAnswerType.reference) &&
          answers.isEmpty) {
        fail(p, '该答案类型须提供答案/参考要点');
      }
      if ((origin == 'none') != answers.isEmpty ||
          (type == TextbookAnswerType.none && answers.isNotEmpty) ||
          (origin == 'textbook' && answerPages.isEmpty) ||
          (origin != 'textbook' && answerPages.isNotEmpty)) {
        fail(p, '答案、来源和类型不一致');
      }
      if (type == TextbookAnswerType.exact && origin == 'reviewerReference') {
        fail(p, '审核者参考要点不能冒充唯一标准答案');
      }
      exercises.add(
        TextbookCourseExercise._(
          id(exercise['id'], '$p.id'),
          p,
          sources(exercise['sources'], '$p.sources'),
          review(exercise['review'], '$p.review'),
          exercise,
          string(exercise['prompt'], '$p.prompt'),
          type,
          answers,
          origin,
          answerPages,
        ),
      );
    }
    return TextbookCourseLesson._(
      key,
      path,
      pages,
      reviewed,
      raw,
      unitId,
      title,
      kind,
      number,
      Map.unmodifiable(coverage),
      text,
      List.unmodifiable(recognition),
      List.unmodifiable(writing),
      List.unmodifiable(words),
      List.unmodifiable(recitations),
      List.unmodifiable(exercises),
    );
  }
}
