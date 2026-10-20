// lib/core/services/update/update_client.dart
//
// 层级：core/services/update
// 职责：检查更新、下载 APK、SHA256 校验。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:poemath/core/services/bounded_http_client.dart';
import 'package:path_provider/path_provider.dart';

import 'package:poemath/core/services/update/update_models.dart';

typedef TemporaryDirectoryProvider = Future<Directory> Function();

/// 更新检查 URL 未配置时抛出。
class UpdateConfigurationException implements Exception {
  const UpdateConfigurationException([this.message]);

  final String? message;

  @override
  String toString() => message ?? 'UPDATE_CHECK_URL is not configured.';
}

/// 更新过程中的通用错误。
class UpdateException implements Exception {
  const UpdateException(this.message, {this.statusCode, this.payload});

  final String message;
  final int? statusCode;
  final Object? payload;

  @override
  String toString() => message;
}

/// 用户取消下载时抛出。
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();

  @override
  String toString() => 'Download cancelled.';
}

/// 下载取消令牌。
class UpdateDownloadCancelToken {
  bool _isCancelled = false;
  final Completer<void> _abortCompleter = Completer<void>();

  bool get isCancelled => _isCancelled;
  Future<void> get abortTrigger => _abortCompleter.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _abortCompleter.complete();
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const UpdateCancelledException();
  }
}

/// 更新检查客户端。
class UpdateClient {
  /// APK 下载大小硬上限（默认 512 MB），防止更新源被劫持后磁盘被写爆。
  static const int _defaultMaxDownloadBytes = 512 * 1024 * 1024;

  UpdateClient({
    required String updateUrl,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 30),
    TemporaryDirectoryProvider? temporaryDirectoryProvider,
    int maxDownloadBytes = _defaultMaxDownloadBytes,
  })  : maxDownloadBytes = maxDownloadBytes,
        _updateUrl = updateUrl.trim(),
        _client = client ?? http.Client(),
        _requestTimeout = requestTimeout,
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        '必须大于零',
      );
    }
    if (maxDownloadBytes <= 0) {
      throw ArgumentError.value(
        maxDownloadBytes,
        'maxDownloadBytes',
        '必须大于零',
      );
    }
  }

  final String _updateUrl;
  final http.Client _client;
  final Duration _requestTimeout;
  final TemporaryDirectoryProvider _temporaryDirectoryProvider;

  /// 下载大小上限；测试注入小上限验证超限中断路径（@visibleForTesting 语义）。
  @visibleForTesting
  final int maxDownloadBytes;

  /// 更新 URL 是否已配置（可解析出 scheme 与 host）。
  ///
  /// 与 [isSecure] 是两回事：这里只回答「填了没」，不回答「填得安全吗」，
  /// 两种情况的用户提示文案不同，不能合并判断。
  bool get isConfigured {
    final uri = Uri.tryParse(_updateUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// 更新 URL 是否走安全传输（HTTPS，或回环地址）。
  ///
  /// 更新接口的响应里同时包含 APK 地址和 SHA256 校验值：明文 HTTP 下中间人
  /// 可以把两者一起替换，校验值校验的就是攻击者自己的包，等于零防护。
  /// 因此检查与下载两段都强制 HTTPS，仅放开回环地址用于本地联调。
  bool get isSecure {
    final uri = Uri.tryParse(_updateUrl);
    return uri != null && _isSecureUri(uri);
  }

  /// HTTPS 一律放行；明文 HTTP 仅在回环地址（本机联调）放行。
  static bool _isSecureUri(Uri uri) {
    if (uri.isScheme('https')) return true;
    if (!uri.isScheme('http')) return false;
    final host = uri.host.toLowerCase();
    // Uri.host 已剥离 IPv6 的方括号，故这里比对裸 `::1`。
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  /// 获取最新版本信息。
  Future<AppUpdateInfo> fetchLatest() async {
    final uri = _updateUri();
    final http.Response response;
    try {
      response =
          await BoundedHttpClient(_client, timeout: _requestTimeout).request(
        'GET',
        uri,
        headers: const {'Accept': 'application/json'},
      );
    } on http.RequestAbortedException {
      throw const UpdateException('检查更新超时');
    } on TimeoutException {
      throw const UpdateException('检查更新超时');
    }
    final payload = _readPayload(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException(
        _messageFromPayload(payload, '检查更新失败'),
        statusCode: response.statusCode,
        payload: payload,
      );
    }
    if (payload is Map<String, dynamic>) {
      final update = AppUpdateInfo.fromJson(payload);
      _validateUpdate(update);
      return update;
    }
    throw UpdateException(
      '更新接口返回格式不正确',
      statusCode: response.statusCode,
      payload: payload,
    );
  }

  /// 拉取版本历史（`history.json`，与 `latest.json` 同目录）。
  ///
  /// 返回**已按 versionCode 降序**的列表（最新在前）。任何失败都返回空
  /// 列表而非抛出 —— 版本历史是**附加信息**，展示不了不该拖垮「检查更新」
  /// 这条主链路（用户真正关心的是有没有新版本、能不能装）。
  Future<List<AppVersionHistoryEntry>> fetchHistory() async {
    // 与 fetchLatest 同源，未配置/非安全地址在此同样不可用。
    final Uri uri;
    try {
      final base = _updateUri();
      uri = base.replace(
        pathSegments: [
          ...base.pathSegments.take(base.pathSegments.length - 1),
          'history.json',
        ],
      );
    } on Object {
      return const [];
    }
    try {
      final response =
          await BoundedHttpClient(_client, timeout: _requestTimeout).request(
        'GET',
        uri,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final payload = jsonDecode(response.body);
      // 接受「裸数组」与「{versions: [...]}」两种形态：前者直观，后者留了
      // 加字段（如 generatedAt）的余地，两种都不必改客户端。
      final raw = switch (payload) {
        final List<dynamic> list => list,
        final Map<String, dynamic> map when map['versions'] is List =>
          map['versions'] as List<dynamic>,
        _ => const <dynamic>[],
      };
      final entries = <AppVersionHistoryEntry>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final entry = AppVersionHistoryEntry.fromJson(item);
        if (entry.versionName.isEmpty) continue;
        entries.add(entry);
      }
      entries.sort((a, b) => b.versionCode.compareTo(a.versionCode));
      return List.unmodifiable(entries);
    } on Object {
      return const [];
    }
  }

  /// 下载 APK 文件到临时目录。
  Future<File> downloadApk(
    AppUpdateInfo update, {
    void Function(int received, int? total)? onProgress,
    UpdateDownloadCancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(update.apkUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const UpdateException('安装包下载地址不正确');
    }
    // apkUrl 来自更新接口（不可信输入）：明文 HTTP 下中间人可替换安装包，
    // 同一响应里的 sha256 也会被一并替换，校验形同虚设，故强制 HTTPS。
    if (!_isSecureUri(uri)) {
      throw const UpdateException('安装包下载地址必须使用 HTTPS');
    }

    cancelToken?.throwIfCancelled();
    final timeoutAbortCompleter = Completer<void>();
    final abortTrigger = cancelToken == null
        ? timeoutAbortCompleter.future
        : Future.any<void>([
            cancelToken.abortTrigger,
            timeoutAbortCompleter.future,
          ]);
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abortTrigger,
    );
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(
        _requestTimeout,
        onTimeout: () {
          if (!timeoutAbortCompleter.isCompleted) {
            timeoutAbortCompleter.complete();
          }
          throw TimeoutException('等待安装包响应超时');
        },
      );
    } on http.RequestAbortedException {
      _throwDownloadInterrupted(cancelToken);
    } on TimeoutException {
      _throwDownloadInterrupted(cancelToken);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('安装包下载失败', statusCode: response.statusCode);
    }

    cancelToken?.throwIfCancelled();
    final directory = await _temporaryDirectoryProvider();
    final updateDirectory = Directory('${directory.path}/poemath_update');
    if (!await updateDirectory.exists()) {
      await updateDirectory.create(recursive: true);
    }
    // versionName 来自更新源（不可信输入），文件名拼接前做字符白名单消毒，
    // 防止 `../evil` 之类的路径遍历写出下载目录；不命中白名单用 'app' 兜底。
    // versionCode 是已验证 >0 的 int，天然安全。
    final safeVersionName =
        RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(update.versionName)
            ? update.versionName
            : 'app';
    final file = File(
      '${updateDirectory.path}/poemath-$safeVersionName+${update.versionCode}.apk',
    );

    final responseLength = response.contentLength;
    final total = responseLength != null && responseLength > 0
        ? responseLength
        : update.apkSize;
    var received = 0;
    final sink = file.openWrite();
    try {
      final responseStream = response.stream.timeout(
        _requestTimeout,
        onTimeout: (eventSink) {
          if (!timeoutAbortCompleter.isCompleted) {
            timeoutAbortCompleter.complete();
          }
          eventSink
            ..addError(TimeoutException('安装包下载数据等待超时'))
            ..close();
        },
      );
      await for (final chunk in responseStream) {
        cancelToken?.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        // 大小硬上限：更新源被劫持前提下的磁盘耗尽纵深防御，
        // 超限中断下载并清理半成品文件。
        if (received > maxDownloadBytes) {
          throw const UpdateException('安装包超出大小上限，已中止下载');
        }
        onProgress?.call(received, total > 0 ? total : null);
      }
      cancelToken?.throwIfCancelled();
      await sink.close();
    } on UpdateCancelledException {
      await _discardPartialFile(file, sink);
      rethrow;
    } on http.RequestAbortedException {
      await _discardPartialFile(file, sink);
      _throwDownloadInterrupted(cancelToken);
    } on TimeoutException {
      await _discardPartialFile(file, sink);
      _throwDownloadInterrupted(cancelToken);
    } catch (_) {
      await _discardPartialFile(file, sink);
      rethrow;
    }
    onProgress?.call(received, total > 0 ? total : null);
    return file;
  }

  /// 计算文件 SHA256 校验值。
  Future<String> sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Uri _updateUri() {
    if (!isConfigured) throw const UpdateConfigurationException();
    final uri = Uri.parse(_updateUrl);
    if (!_isSecureUri(uri)) {
      throw const UpdateConfigurationException(
        '更新检查地址必须使用 HTTPS，当前配置已被拒绝。',
      );
    }
    return uri;
  }

  Object? _readPayload(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return response.body;
    }
  }

  String _messageFromPayload(Object? payload, String fallback) {
    if (payload is String && payload.trim().isNotEmpty) return payload.trim();
    if (payload is Map<String, dynamic>) {
      final error = payload['error'] ?? payload['message'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return fallback;
  }

  void _validateUpdate(AppUpdateInfo update) {
    if (update.packageName.isEmpty) {
      throw const UpdateException('更新信息缺少包名');
    }
    if (update.versionName.isEmpty) {
      throw const UpdateException('更新信息缺少版本号');
    }
    if (update.versionCode <= 0) {
      throw const UpdateException('更新信息版本号不正确');
    }
    if (update.apkUrl.isEmpty) {
      throw const UpdateException('更新信息缺少安装包地址');
    }
    if (!_isSha256(update.apkSha256)) {
      throw const UpdateException('更新信息缺少有效校验值');
    }
  }

  bool _isSha256(String value) {
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
  }

  Never _throwDownloadInterrupted(UpdateDownloadCancelToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) {
      throw const UpdateCancelledException();
    }
    throw const UpdateException('安装包下载超时');
  }

  Future<void> _discardPartialFile(File file, IOSink sink) async {
    try {
      await sink.close();
    } catch (_) {
      // Preserve the download error while still attempting file cleanup.
    }
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cleanup is best-effort; the original error remains actionable.
    }
  }
}
