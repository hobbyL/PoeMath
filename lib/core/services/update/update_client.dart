// lib/core/services/update/update_client.dart
//
// 层级：core/services/update
// 职责：检查更新、下载 APK、SHA256 校验。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
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
  UpdateClient({
    required String updateUrl,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 30),
    TemporaryDirectoryProvider? temporaryDirectoryProvider,
  })  : _updateUrl = updateUrl.trim(),
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
  }

  final String _updateUrl;
  final http.Client _client;
  final Duration _requestTimeout;
  final TemporaryDirectoryProvider _temporaryDirectoryProvider;

  /// 更新 URL 是否有效。
  bool get isConfigured {
    final uri = Uri.tryParse(_updateUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// 获取最新版本信息。
  Future<AppUpdateInfo> fetchLatest() async {
    final uri = _updateUri();
    final http.Response response;
    try {
      final abortTrigger = Future<void>.delayed(_requestTimeout);
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abortTrigger,
      )..headers['Accept'] = 'application/json';
      final streamedResponse = await _client.send(request).timeout(
            _requestTimeout,
          );
      response = await http.Response.fromStream(streamedResponse).timeout(
        _requestTimeout,
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
    final file = File(
      '${updateDirectory.path}/poemath-${update.versionName}+${update.versionCode}.apk',
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
    return Uri.parse(_updateUrl);
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
