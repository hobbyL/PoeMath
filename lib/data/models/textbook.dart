enum TextbookSubject {
  chinese('语文'),
  math('数学'),
  english('英语'),
  unknown('待确认学科');

  const TextbookSubject(this.label);
  final String label;
}

// 教材身份与用户阅读记录；PDF-only 不代表已审核的课程内容。
class Textbook {
  const Textbook({
    required this.pdfSha256,
    required this.title,
    required this.grade,
    required this.semester,
    required this.publisher,
    required this.editionNote,
    required this.originalFileName,
    required this.pageCount,
    required this.fileSize,
    required this.importedAt,
    this.subject = TextbookSubject.unknown,
    this.editionId,
    this.curriculumStandard,
  });

  final String pdfSha256;
  final String title;
  final int grade;
  final String semester;
  final String publisher;
  final String editionNote;
  final String originalFileName;
  final int pageCount;
  final int fileSize;
  final DateTime importedAt;
  final TextbookSubject subject;
  final String? editionId;
  final String? curriculumStandard;
  String get learningEditionId => editionId ?? 'pdf-$pdfSha256';

  Textbook withSubject(TextbookSubject subject) => Textbook(
    pdfSha256: pdfSha256,
    title: title,
    grade: grade,
    semester: semester,
    publisher: publisher,
    editionNote: editionNote,
    originalFileName: originalFileName,
    pageCount: pageCount,
    fileSize: fileSize,
    importedAt: importedAt,
    subject: subject,
    editionId: editionId,
    curriculumStandard: curriculumStandard,
  );

  String get volumeLabel => '${gradeLabels[grade]}$semester册';
  static const gradeLabels = {
    1: '一年级',
    2: '二年级',
    3: '三年级',
    4: '四年级',
    5: '五年级',
    6: '六年级',
  };
  static bool isValidId(String id) => RegExp(r'^[a-f0-9]{64}$').hasMatch(id);

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'subject': subject.name,
    if (editionId != null) 'editionId': editionId,
    if (curriculumStandard != null) 'curriculumStandard': curriculumStandard,
    'pdfSha256': pdfSha256,
    'title': title,
    'grade': grade,
    'semester': semester,
    'publisher': publisher,
    'editionNote': editionNote,
    'originalFileName': originalFileName,
    'pageCount': pageCount,
    'fileSize': fileSize,
    'importedAt': importedAt.toIso8601String(),
    'editionVerification': 'unverified',
    'contentStatus': 'pdfOnly',
  };

  factory Textbook.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version != 1 && version != 2) {
      throw const FormatException('教材信息版本无法识别');
    }
    final subject = version == 1
        ? TextbookSubject.unknown
        : TextbookSubject.values
              .where((value) => value.name == json['subject'])
              .firstOrNull;
    if (subject == null) throw const FormatException('教材学科无效');
    final book = Textbook(
      pdfSha256: json['pdfSha256'] as String,
      title: json['title'] as String,
      grade: json['grade'] as int,
      semester: json['semester'] as String,
      publisher: json['publisher'] as String,
      editionNote: json['editionNote'] as String,
      originalFileName: json['originalFileName'] as String,
      pageCount: json['pageCount'] as int,
      fileSize: json['fileSize'] as int,
      importedAt: DateTime.parse(json['importedAt'] as String),
      subject: subject,
      editionId: json['editionId'] as String?,
      curriculumStandard: json['curriculumStandard'] as String?,
    );
    if (!isValidId(book.pdfSha256) ||
        book.title.trim().isEmpty ||
        !gradeLabels.containsKey(book.grade) ||
        !const ['上', '下'].contains(book.semester) ||
        book.pageCount < 1 ||
        book.fileSize < 1) {
      throw const FormatException('教材信息无效');
    }
    if (book.editionId != null &&
            (book.editionId!.trim().isEmpty || book.editionId!.length > 160) ||
        book.curriculumStandard != null &&
            (book.curriculumStandard!.trim().isEmpty ||
                book.curriculumStandard!.length > 200)) {
      throw const FormatException('教材版次或课标信息无效');
    }
    return book;
  }
}

enum TextbookMatch {
  unchecked('待核对'),
  matches('与手中教材一致'),
  differs('与手中教材不同');

  const TextbookMatch(this.label);
  final String label;
}

class TextbookReading {
  const TextbookReading({this.page = 1, this.match = TextbookMatch.unchecked});
  final int page;
  final TextbookMatch match;
  Map<String, dynamic> toJson() => {'page': page, 'match': match.name};
  factory TextbookReading.fromJson(Map<String, dynamic> json) =>
      TextbookReading(
        page: json['page'] is int && (json['page'] as int) > 0
            ? json['page'] as int
            : 1,
        match: TextbookMatch.values.firstWhere(
          (value) => value.name == json['match'],
          orElse: () => TextbookMatch.unchecked,
        ),
      );
}
