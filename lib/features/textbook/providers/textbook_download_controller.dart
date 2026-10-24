import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';

enum TextbookDownloadStatus { downloading, verifying, failed, cancelled }

class TextbookDownloadState {
  const TextbookDownloadState(this.status, {this.progress = 0, this.message});
  final TextbookDownloadStatus status;
  final double progress;
  final String? message;
  bool get active =>
      status == TextbookDownloadStatus.downloading ||
      status == TextbookDownloadStatus.verifying;
  String get label => switch (status) {
        TextbookDownloadStatus.downloading =>
          '下载中 ${(progress * 100).floor()}%',
        TextbookDownloadStatus.verifying => '校验文件中',
        TextbookDownloadStatus.failed => message ?? '下载失败，请重试',
        TextbookDownloadStatus.cancelled => '已取消下载',
      };
}

/// 下载属于应用级会话，导航到阅读/管理页面不会中断传输。
class TextbookDownloadController
    extends StateNotifier<Map<String, TextbookDownloadState>> {
  TextbookDownloadController(this._files, this._repo, this._onInstalled)
      : super({});
  final TextbookFileService _files;
  final TextbookRepository _repo;
  final void Function(String id) _onInstalled;
  final _tokens = <String, TextbookImportToken>{};

  void _set(String id, TextbookDownloadState value) {
    if (mounted) state = {...state, id: value};
  }

  Future<void> download(TextbookCatalogEntry entry) async {
    final id = entry.book.pdfSha256;
    if (_tokens.containsKey(id)) return;
    final token = TextbookImportToken();
    _tokens[id] = token;
    _set(id, const TextbookDownloadState(TextbookDownloadStatus.downloading));
    try {
      await _files.downloadPdf(
        entry: entry,
        token: token,
        onProgress: (copied, total) {
          final progress = (copied / total).clamp(0.0, 1.0);
          if (!mounted) return;
          final previous = state[id];
          if (copied == total ||
              (progress * 100).floor() !=
                  ((previous?.progress ?? 0) * 100).floor()) {
            _set(
              id,
              TextbookDownloadState(
                copied == total
                    ? TextbookDownloadStatus.verifying
                    : TextbookDownloadStatus.downloading,
                progress: progress,
              ),
            );
          }
        },
      );
      await _repo.addIfAbsent(
        Textbook.fromJson({
          ...entry.book.toJson(),
          'importedAt': DateTime.now().toIso8601String(),
        }),
      );
      if (mounted) {
        _onInstalled(id);
        state = {...state}..remove(id);
      }
    } on TextbookDownloadCancelled {
      _set(id, const TextbookDownloadState(TextbookDownloadStatus.cancelled));
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '教材下载失败',
        tag: 'Textbook',
        error: error,
        stackTrace: stackTrace,
      );
      _set(
        id,
        TextbookDownloadState(
          TextbookDownloadStatus.failed,
          message:
              error is TextbookFileException ? error.message : '教材登记失败，请重试下载',
        ),
      );
    } finally {
      _tokens.remove(id);
    }
  }

  void cancel(String id) => _tokens[id]?.cancel();

  @override
  void dispose() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    super.dispose();
  }
}
