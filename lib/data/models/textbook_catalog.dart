import 'package:poemath/data/models/textbook.dart';

/// 随应用发布的轻量书目；PDF 由用户直接从固定版本的公开上游获取。
class TextbookCatalogEntry {
  const TextbookCatalogEntry({
    required this.book,
    required this.downloadUrl,
    required this.sourceRepository,
    required this.sourceCommit,
    required this.sourcePath,
    required this.editionLabel,
    required this.evidencePdfPages,
    this.sourceBlobSha,
    this.coverAsset,
    this.coverSha256,
    this.publicationDate,
    this.editionNumber,
    this.printingDate,
    this.printingNumber,
    this.approvalYear,
  });

  final Textbook book;
  final Uri downloadUrl;
  final String sourceRepository;
  final String sourceCommit;
  final String sourcePath;
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
  Uri? get fallbackDownloadUrl => sourceBlobSha == null
      ? null
      : Uri.https(
          'api.github.com',
          '/repos/$sourceRepository/git/blobs/$sourceBlobSha',
        );

  factory TextbookCatalogEntry.fromJson(Map<String, dynamic> json) {
    final uri = Uri.parse(json['downloadUrl'] as String);
    final repository = json['sourceRepository'] as String;
    final commit = json['sourceCommit'] as String;
    final path = json['sourcePath'] as String;
    final pages = (json['evidencePdfPages'] as List).cast<int>();
    final book = Textbook.fromJson({
      // 已发布的 v1 目录全部为已核验的语文书目；不能按本地书名猜测学科。
      'schemaVersion': 2,
      'subject': json['subject'] ?? 'chinese',
      'pdfSha256': json['sha256'],
      'title': json['title'],
      'grade': json['grade'],
      'semester': json['semester'],
      'publisher': json['publisher'],
      'editionNote': json['editionNotes'],
      'originalFileName': path.split('/').last,
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
    if (uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.join('/') != '$repository/$commit/$path' ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(commit) ||
        (blob != null && !RegExp(r'^[a-f0-9]{40}$').hasMatch(blob)) ||
        edition.trim().isEmpty ||
        pages.isEmpty ||
        pages.any((page) => page < 1 || page > book.pageCount) ||
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
    );
  }
}
