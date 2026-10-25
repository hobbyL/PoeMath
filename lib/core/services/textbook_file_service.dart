import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';

class TextbookFileException implements Exception {
  const TextbookFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TextbookImportCancelled extends TextbookFileException {
  const TextbookImportCancelled() : super('已取消导入');
}

class TextbookDownloadCancelled extends TextbookFileException {
  const TextbookDownloadCancelled() : super('已取消下载');
}

class TextbookImportToken {
  bool _cancelled = false;
  final _abort = Completer<void>();
  Future<void> get abortTrigger => _abort.future;
  void cancel() {
    _cancelled = true;
    if (!_abort.isCompleted) _abort.complete();
  }

  void check() {
    if (_cancelled) throw const TextbookImportCancelled();
  }
}

typedef TextbookPdfValidator = Future<int> Function(String path);
typedef TextbookImportProgress = void Function(int copied, int total);

class ImportedTextbookFile {
  const ImportedTextbookFile({
    required this.sha256,
    required this.pageCount,
    required this.size,
  });
  final String sha256;
  final int pageCount;
  final int size;
}

/// 大文件始终流式读取；文件名只从 SHA 派生，不信任来源文件名。
class TextbookFileService {
  TextbookFileService({
    Future<Directory> Function()? directoryProvider,
    Future<Directory?> Function()? pickerCacheDirectoryProvider,
    NarrationAudioCache? narrationAudioCache,
    TextbookPdfValidator? validator,
    http.Client Function()? clientFactory,
    Duration requestTimeout = const Duration(seconds: 30),
    this.maxFileSize = 250 * 1024 * 1024,
  })  : narrationCache = narrationAudioCache ??
            NarrationAudioCache(
              directoryProvider: directoryProvider ?? getTemporaryDirectory,
            ),
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory,
        _pickerCacheDirectoryProvider =
            pickerCacheDirectoryProvider ?? _pickerCacheDirectory,
        _validator = validator ?? _validatePdf,
        _clientFactory = clientFactory ?? http.Client.new,
        _requestTimeout = requestTimeout;
  final Future<Directory> Function() _directoryProvider;
  final Future<Directory?> Function() _pickerCacheDirectoryProvider;
  final TextbookPdfValidator _validator;
  final http.Client Function() _clientFactory;
  final Duration _requestTimeout;
  final int maxFileSize;
  Future<void> _operations = Future<void>.value();
  final _contentCaches = <String, TextbookContentCache>{};
  final NarrationAudioCache narrationCache;

  TextbookContentCache contentCache(Textbook book) =>
      _contentCaches.putIfAbsent(
        book.pdfSha256,
        () => TextbookContentCache(
          book: book,
          directoryProvider: _directoryProvider,
        ),
      );

  static Future<Directory?> _pickerCacheDirectory() async {
    if (!Platform.isAndroid) return null;
    return Directory('${(await getTemporaryDirectory()).path}/file_picker');
  }

  /// 只清理 Android picker 本次选择的缓存副本，不删除用户原文件。
  Future<void> discardPickerCopy(String sourcePath) async {
    final cache = await _pickerCacheDirectoryProvider();
    final source = File(sourcePath);
    if (cache == null || !await cache.exists() || !await source.exists()) {
      return;
    }
    final cachePath = await cache.resolveSymbolicLinks();
    final sourceResolved = await source.resolveSymbolicLinks();
    if (sourceResolved.startsWith('$cachePath${Platform.pathSeparator}')) {
      await source.delete();
    }
  }

  static Future<int> _validatePdf(String path) async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(path);
    try {
      if (document.isEncrypted) {
        throw const TextbookFileException('请先移除 PDF 的密码保护，再导入');
      }
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  Future<Directory> _directory() async {
    final base = await _directoryProvider();
    return Directory('${base.path}/textbooks').create(recursive: true);
  }

  Future<File> _file(String id) async {
    if (!Textbook.isValidId(id)) throw const TextbookFileException('教材身份无效');
    return File('${(await _directory()).path}/$id.pdf');
  }

  Future<String?> installedPath(Textbook book) async {
    final file = await _file(book.pdfSha256);
    if (await file.exists() && await file.length() == book.fileSize) {
      return file.path;
    }
    await contentCache(book).clear();
    return null;
  }

  Future<ImportedTextbookFile> importPdf({
    required String sourcePath,
    required TextbookImportToken token,
    TextbookImportProgress? onProgress,
  }) {
    final result =
        _operations.then((_) => _importPdf(sourcePath, token, onProgress));
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<ImportedTextbookFile> _importPdf(
    String sourcePath,
    TextbookImportToken token,
    TextbookImportProgress? onProgress,
  ) async {
    token.check();
    try {
      final source = File(sourcePath);
      return await _storePdf(
        stream: source.openRead(),
        expectedSize: await source.length(),
        token: token,
        onProgress: onProgress,
      );
    } on TextbookFileException {
      rethrow;
    } on Exception {
      throw const TextbookFileException('PDF 无法导入，请检查文件是否损坏、加密或存储空间不足');
    }
  }

  Future<ImportedTextbookFile> downloadPdf({
    required TextbookCatalogEntry entry,
    required TextbookImportToken token,
    TextbookImportProgress? onProgress,
  }) {
    final result = _operations.then((_) async {
      try {
        return await _downloadPdfFromUrl(
          entry,
          entry.downloadUrl,
          token,
          onProgress,
        );
      } on TextbookDownloadCancelled {
        rethrow;
      } on TextbookFileException {
        final fallback = entry.fallbackDownloadUrl;
        if (fallback == null) rethrow;
        return _downloadPdfFromUrl(
          entry,
          fallback,
          token,
          onProgress,
          fallback: true,
        );
      }
    });
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<ImportedTextbookFile> _downloadPdfFromUrl(
    TextbookCatalogEntry entry,
    Uri url,
    TextbookImportToken token,
    TextbookImportProgress? onProgress, {
    bool fallback = false,
  }) async {
    final abort = Completer<void>();
    http.Client? client;
    try {
      token.check();
      if (url.scheme != 'https' || !Textbook.isValidId(entry.book.pdfSha256)) {
        throw const TextbookFileException('教材下载地址或校验信息无效');
      }
      if (entry.book.fileSize < 5 || entry.book.fileSize > maxFileSize) {
        throw const TextbookFileException('PDF 超过大小上限');
      }
      onProgress?.call(0, entry.book.fileSize);
      client = _clientFactory();
      final request = http.AbortableRequest(
        'GET',
        url,
        abortTrigger: Future.any([token.abortTrigger, abort.future]),
      )..followRedirects = false;
      if (fallback) {
        request.headers['Accept'] = 'application/vnd.github.raw+json';
      }
      final response = await client.send(request).timeout(_requestTimeout);
      token.check();
      if (response.statusCode != 200) {
        throw TextbookFileException(
          '教材来源暂时无法下载（${response.statusCode}），请稍后重试',
        );
      }
      if (response.contentLength != null &&
          response.contentLength != entry.book.fileSize) {
        throw const TextbookFileException('教材文件大小与目录不一致，请稍后重试');
      }
      return await _storePdf(
        stream: response.stream.timeout(_requestTimeout),
        expectedSize: entry.book.fileSize,
        expectedSha: entry.book.pdfSha256,
        expectedPages: entry.book.pageCount,
        token: token,
        onProgress: onProgress,
      );
    } on TextbookImportCancelled {
      throw const TextbookDownloadCancelled();
    } on http.RequestAbortedException {
      if (token._cancelled) throw const TextbookDownloadCancelled();
      throw const TextbookFileException('教材下载已中断，请重试');
    } on TimeoutException {
      throw const TextbookFileException('教材下载超时，请检查网络后重试');
    } on TextbookFileException {
      rethrow;
    } on SocketException {
      throw const TextbookFileException('无法连接教材来源，请检查网络后重试');
    } on http.ClientException {
      throw const TextbookFileException('教材下载中断，请检查网络后重试');
    } on Exception {
      throw const TextbookFileException('教材无法保存，请检查文件或存储空间后重试');
    } finally {
      if (!abort.isCompleted) abort.complete();
      client?.close();
    }
  }

  Future<ImportedTextbookFile> _storePdf({
    required Stream<List<int>> stream,
    required int expectedSize,
    required TextbookImportToken token,
    String? expectedSha,
    int? expectedPages,
    TextbookImportProgress? onProgress,
  }) async {
    File? pending;
    RandomAccessFile? output;
    try {
      token.check();
      if (expectedSize < 5 || expectedSize > maxFileSize) {
        throw const TextbookFileException('请选择有效 PDF，文件不能超过 250 MB');
      }
      final directory = await _directory();
      pending = File(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.pending',
      );
      output = await pending.open(mode: FileMode.writeOnly);
      var copied = 0;
      final header = <int>[];
      await for (final bytes in stream) {
        token.check();
        copied += bytes.length;
        if (copied > maxFileSize || copied > expectedSize) {
          throw const TextbookFileException('PDF 超过大小上限');
        }
        if (header.length < 5) header.addAll(bytes.take(5 - header.length));
        await output.writeFrom(bytes);
        onProgress?.call(copied, expectedSize);
      }
      await output.flush();
      await output.close();
      output = null;
      token.check();
      if (copied != expectedSize || String.fromCharCodes(header) != '%PDF-') {
        throw const TextbookFileException('文件不是完整的 PDF，请重新选择');
      }
      final digest = (await sha256.bind(pending.openRead()).first).toString();
      token.check();
      if (expectedSha != null && digest != expectedSha) {
        throw const TextbookFileException('教材文件校验失败，请重新下载');
      }
      final pages = await _validator(pending.path);
      if (pages < 1 || pages > 5000) {
        throw const TextbookFileException('PDF 页数无效或超过 5000 页');
      }
      if (expectedPages != null && pages != expectedPages) {
        throw const TextbookFileException('教材页数与目录不一致，请重新下载');
      }
      token.check();
      final target = await _file(digest);
      token.check();
      // 原子发布已验证副本。崩溃或取消永远不替换为半份文件。
      await pending.rename(target.path);
      pending = null;
      return ImportedTextbookFile(
        sha256: digest,
        pageCount: pages,
        size: copied,
      );
    } on TextbookFileException {
      rethrow;
    } finally {
      await output?.close();
      if (pending != null && await pending.exists()) await pending.delete();
    }
  }

  /// 删除原书及派生缓存，书目/阅读记录由仓储保留。
  Future<void> removePdf(String id) {
    final result = _operations.then((_) async {
      final file = await _file(id);
      await narrationCache.clearBook(id);
      final cache = _contentCaches[id];
      if (cache != null) {
        await cache.clear();
      } else {
        final directory = Directory('${(await _directory()).path}/cache/$id');
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      if (await file.exists()) await file.delete();
    });
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
