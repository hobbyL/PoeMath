import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/data/repositories/textbook_download_repository.dart';

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
    TextbookDownloadStatus.downloading => '下载中 ${(progress * 100).floor()}%',
    TextbookDownloadStatus.verifying => '校验文件中',
    TextbookDownloadStatus.failed => message ?? '下载失败，请重试',
    TextbookDownloadStatus.cancelled => '已取消下载',
  };
}

/// 下载属于应用级会话；未完成意图跨重启保留，主动取消才移除。
class TextbookDownloadController
    extends StateNotifier<Map<String, TextbookDownloadState>> {
  TextbookDownloadController(
    this._files,
    this._repo,
    this._onInstalled, {
    this._downloads,
  }) : super({});
  final TextbookFileService _files;
  final TextbookRepository _repo;
  final void Function(String id) _onInstalled;
  final TextbookDownloadRepository? _downloads;
  final _tokens = <String, TextbookImportToken>{};
  final _cancellations = <String, Future<bool>>{};
  Future<void>? _restoring;

  void _set(String id, TextbookDownloadState value) {
    if (mounted) state = {...state, id: value};
  }

  /// 恢复当前目录中曾由用户发起的任务，导航/前台重复调用不会重复请求。
  Future<void> restorePending(List<TextbookCatalogEntry> catalog) {
    return _restoring ??= _restorePending(catalog)
        .whenComplete(() => _restoring = null);
  }

  Future<void> _restorePending(List<TextbookCatalogEntry> catalog) async {
    final ids = _downloads?.pendingIds() ?? const <String>{};
    await Future.wait([
      for (final entry in catalog)
        if (mounted && ids.contains(entry.book.pdfSha256))
          _download(entry, restoring: true),
    ]);
  }

  Future<void> download(TextbookCatalogEntry entry) => _download(entry);

  Future<void> _download(
    TextbookCatalogEntry entry, {
    bool restoring = false,
  }) async {
    final id = entry.book.pdfSha256;
    if (!mounted || _tokens.containsKey(id)) return;
    final token = TextbookImportToken();
    _tokens[id] = token;
    _set(id, const TextbookDownloadState(TextbookDownloadStatus.downloading));
    try {
      // 意图落盘完成后才发起网络请求，进程随时退出也有恢复入口。
      await _downloads?.markPending(id);
      if (!restoring || await _files.installedPath(entry.book) == null) {
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
      }
      if (!mounted || _cancellations.containsKey(id)) {
        throw const TextbookDownloadCancelled();
      }
      await _repo.addIfAbsent(
        Textbook.fromJson({
          ...entry.book.toJson(),
          'importedAt': DateTime.now().toIso8601String(),
        }),
      );
      await _downloads?.remove(id);
      if (mounted) {
        _onInstalled(id);
        state = {...state}..remove(id);
      }
    } on TextbookDownloadCancelled {
      final cancellation = _cancellations[id];
      if (cancellation != null && !await cancellation) return;
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
          message: error is TextbookFileException
              ? error.message
              : '教材登记失败，请重试下载',
        ),
      );
    } finally {
      _tokens.remove(id);
      _cancellations.remove(id);
    }
  }

  void cancel(String id) {
    final token = _tokens[id];
    if (token == null || _cancellations.containsKey(id)) return;
    // 排队任务可能还在等待其他书籍，取消意图不能等传输队列轮到它才落盘。
    _cancellations[id] = _removeCancelledIntent(id);
    token.cancel();
  }

  Future<bool> _removeCancelledIntent(String id) async {
    try {
      await _downloads?.remove(id);
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '教材下载取消状态无法保存',
        tag: 'Textbook',
        error: error,
        stackTrace: stackTrace,
      );
      _set(
        id,
        const TextbookDownloadState(
          TextbookDownloadStatus.failed,
          message: '取消状态保存失败，请重试',
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    for (final token in _tokens.values) {
      token.cancel(preservePartial: true);
    }
    super.dispose();
  }
}
