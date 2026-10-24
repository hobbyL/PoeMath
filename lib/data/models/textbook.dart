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
        'schemaVersion': 1,
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
    );
    if (json['schemaVersion'] != 1 ||
        !isValidId(book.pdfSha256) ||
        book.title.trim().isEmpty ||
        !gradeLabels.containsKey(book.grade) ||
        !const ['上', '下'].contains(book.semester) ||
        book.pageCount < 1 ||
        book.fileSize < 1) {
      throw const FormatException('教材信息无效');
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
