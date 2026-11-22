import 'package:poemath/data/models/textbook.dart';

enum TextbookCatalogSourceKind { githubRaw, mathApi }

/// 随应用发布的轻量书目；PDF 由用户直接从固定版本的公开上游获取。
class TextbookCatalogEntry {
  const TextbookCatalogEntry({
    required this.book,
    required this.downloadUrl,
    required this.editionLabel,
    required this.evidencePdfPages,
    this.sourceKind = TextbookCatalogSourceKind.githubRaw,
    this.sourceRepository,
    this.sourceCommit,
    this.sourcePath,
    this.sourceBlobSha,
    this.coverAsset,
    this.coverSha256,
    this.publicationDate,
    this.editionNumber,
    this.printingDate,
    this.printingNumber,
    this.approvalYear,
    this.downloadable = true,
    this.supportsMathCourseGeneration = true,
  });

  final Textbook book;
  final Uri downloadUrl;
  final TextbookCatalogSourceKind sourceKind;
  final String? sourceRepository;
  final String? sourceCommit;
  final String? sourcePath;
  final String editionLabel;
  final List<int> evidencePdfPages;
  final String? sourceBlobSha;
  final String? coverAsset;
  final String? coverSha256;
  final String? publicationDate;
  final int? editionNumber;
  final String? printingDate;
  final int? printingNumber;
  final int? approvalYear;
  final bool downloadable;
  final bool supportsMathCourseGeneration;
  Uri? get fallbackDownloadUrl =>
      sourceKind != TextbookCatalogSourceKind.githubRaw ||
          sourceBlobSha == null ||
          sourceRepository == null
      ? null
      : Uri.https(
          'api.github.com',
          '/repos/$sourceRepository/git/blobs/$sourceBlobSha',
        );

  factory TextbookCatalogEntry.fromJson(Map<String, dynamic> json) {
    final uri = Uri.parse(json['downloadUrl'] as String);
    final rawSourceKind = json['sourceKind'];
    final sourceKind = switch (rawSourceKind) {
      null || 'githubRaw' => TextbookCatalogSourceKind.githubRaw,
      'mathApi' => TextbookCatalogSourceKind.mathApi,
      _ => throw const FormatException('教材来源类型无效'),
    };
    final repository = json['sourceRepository'] as String?;
    final commit = json['sourceCommit'] as String?;
    final path = json['sourcePath'] as String?;
    final pages = (json['evidencePdfPages'] as List).cast<int>();
    final grade = json['grade'] as int;
    final semester = json['semester'] as String;
    final subject = json['subject'] ?? 'chinese';
    final book = Textbook.fromJson({
      // 已发布的 v1 目录全部为已核验的语文书目；不能按本地书名猜测学科。
      'schemaVersion': 2,
      'subject': subject,
      'pdfSha256': json['sha256'],
      'title': json['title'],
      'grade': grade,
      'semester': semester,
      'publisher': json['publisher'],
      'editionNote': json['editionNotes'],
      'originalFileName': path?.split('/').last ?? 'math-$grade-$semester.pdf',
      'pageCount': json['pageCount'],
      'fileSize': json['bytes'],
      'importedAt': json['checkedAt'],
      'editionId': json['editionId'],
      'curriculumStandard': json['curriculumStandard'],
    });
    final edition = json['editionLabel'] as String;
    final blob = json['gitBlobSha'] as String?;
    final cover = json['coverAsset'] as String?;
    final coverHash = json['coverSha256'] as String?;
    final approvalYear = json['approvalYear'] as int?;
    final rawDownloadable = json['downloadable'];
    final rawGeneration = json['supportsMathCourseGeneration'];
    if (rawDownloadable != null && rawDownloadable is! bool ||
        rawGeneration != null && rawGeneration is! bool) {
      throw const FormatException('教材目录状态无效');
    }
    final downloadable = rawDownloadable as bool? ?? true;
    final supportsMathCourseGeneration = rawGeneration as bool? ?? true;
    final sourceValid = switch (sourceKind) {
      TextbookCatalogSourceKind.githubRaw =>
        uri.scheme == 'https' &&
            uri.host == 'raw.githubusercontent.com' &&
            !uri.hasPort &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment &&
            repository != null &&
            repository.trim().isNotEmpty &&
            commit != null &&
            RegExp(r'^[a-f0-9]{40}$').hasMatch(commit) &&
            path != null &&
            path.isNotEmpty &&
            uri.pathSegments.join('/') == '$repository/$commit/$path' &&
            (blob == null || RegExp(r'^[a-f0-9]{40}$').hasMatch(blob)),
      TextbookCatalogSourceKind.mathApi =>
        uri.scheme == 'https' &&
            uri.host == 'www.gostudy.net.cn' &&
            !uri.hasPort &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment &&
            subject == 'math' &&
            repository == null &&
            commit == null &&
            path == null &&
            blob == null &&
            uri.pathSegments.length == 5 &&
            uri.pathSegments[0] == 'api' &&
            uri.pathSegments[1] == 'textbooks' &&
            uri.pathSegments[2] == 'math' &&
            uri.pathSegments[3] == grade.toString() &&
            uri.pathSegments[4] == semester,
    };
    if (!sourceValid ||
        edition.trim().isEmpty ||
        pages.isEmpty ||
        pages.any((page) => page < 1 || page > book.pageCount) ||
        subject != 'math' && !supportsMathCourseGeneration ||
        (cover != null &&
            (cover != 'assets/textbooks/covers/${book.pdfSha256}.webp' ||
                coverHash == null ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(coverHash) ||
                json['coverSourcePdfPage'] != 1)) ||
        (cover == null && coverHash != null) ||
        approvalYear != null && (approvalYear < 1900 || approvalYear > 2099)) {
      throw const FormatException('教材目录信息无效');
    }
    return TextbookCatalogEntry(
      book: book,
      downloadUrl: uri,
      sourceKind: sourceKind,
      sourceRepository: repository,
      sourceCommit: commit,
      sourcePath: path,
      editionLabel: edition,
      evidencePdfPages: List.unmodifiable(pages),
      sourceBlobSha: blob,
      coverAsset: cover,
      coverSha256: coverHash,
      publicationDate: json['publicationDate'] as String?,
      editionNumber: json['editionNumber'] as int?,
      printingDate: json['printingDate'] as String?,
      printingNumber: json['printingNumber'] as int?,
      approvalYear: approvalYear,
      downloadable: downloadable,
      supportsMathCourseGeneration: supportsMathCourseGeneration,
    );
  }
}
