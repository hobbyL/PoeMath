// lib/core/services/update/update_client.dart
//
// 层级：core/services/update
// 职责：检查更新、下载 APK、SHA256 校验。

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:poemath/core/services/update/update_models.dart';

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

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
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
  })  : _updateUrl = updateUrl.trim(),
        _client = client ?? http.Client();

  final String _updateUrl;
  final http.Client _client;

  /// 更新 URL 是否有效。
  bool get isConfigured {
    final uri = Uri.tryParse(_updateUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// 获取最新版本信息。
  Future<AppUpdateInfo> fetchLatest() async {
    final uri = _updateUri();
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
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

    final request = http.Request('GET', uri);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('安装包下载失败', statusCode: response.statusCode);
    }

    final directory = await getTemporaryDirectory();
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
      await for (final chunk in response.stream) {
        cancelToken?.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total > 0 ? total : null);
      }
      cancelToken?.throwIfCancelled();
    } on UpdateCancelledException {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await sink.close();
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
}
