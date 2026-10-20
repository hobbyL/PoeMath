// lib/core/services/webdav_service.dart
//
// 层级：core/services
// 职责：WebDAV 客户端服务 — 通过 WebDAV 协议上传/下载备份文件。
//       使用 http 包发送自定义 HTTP 方法（PROPFIND/MKCOL/PUT/GET）。

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:poemath/core/services/bounded_http_client.dart';

import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/core/utils/logger.dart';

/// WebDAV 备份文件名。
const String _backupFileName = 'poemath_backup.json';

class WebDavBackupVersion {
  const WebDavBackupVersion(this.id, this.createdAt);
  final String id;
  final DateTime createdAt;
}

/// WebDAV 客户端服务。
class WebDavService {
  WebDavService({
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  })  : _client = BoundedHttpClient(
          client ?? http.Client(),
          timeout: timeout,
          maxResponseBytes: 32 * 1024 * 1024,
        ),
        _ownsClient = client == null;

  final BoundedHttpClient _client;
  final bool _ownsClient;
  Duration _deadline(int seconds) {
    final normal = Duration(seconds: seconds);
    return _client.timeout < normal ? _client.timeout : normal;
  }

  static final _versionName =
      RegExp(r'^poemath_backup_(\d+)_[a-f0-9]{8}\.json$');

  /// 释放 HTTP 连接池。
  void dispose() {
    _client.close();
    if (_ownsClient) _client.inner.close();
  }

  /// 测试 WebDAV 连接。
  ///
  /// 向远程根目录发送 PROPFIND 请求，返回是否连通。
  Future<bool> testConnection(WebDavConfig config) async {
    _validateConfig(config);
    // URI 构造放在 try 外：越界属于配置错误，必须抛给调用方，
    // 不能被下面的 `on Exception` 吞成「连接失败」。
    final uri = _remoteUri(config);
    try {
      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(_authHeaders(config));
      request.headers['Depth'] = '0';
      request.headers['Content-Type'] = 'application/xml; charset=utf-8';
      request.body = _propfindBody;

      final response =
          await _client.sendBounded(request, deadline: _deadline(10));
      final statusCode = response.statusCode;
      await response.stream.drain<void>();
      // 207 Multi-Status = WebDAV 成功
      // 404 = 目录不存在（但连通）
      // 401/403 = 认证失败
      return statusCode == 207 || statusCode == 200 || statusCode == 404;
    } on Exception {
      return false;
    }
  }

  /// 上传备份 JSON 到 WebDAV 服务器。
  ///
  /// 自动创建远程目录（如不存在）。
  Future<void> upload(WebDavConfig config, String jsonContent) async {
    _validateConfig(config);
    // 先确保目录存在
    await _ensureDirectory(config);
    final suffix =
        Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0');
    final version =
        'poemath_backup_${DateTime.now().microsecondsSinceEpoch}_$suffix.json';
    // 不可变历史版本先写成功，再发布兼容旧客户端的 latest 文件。
    await _put(config, version, jsonContent);
    await _put(config, _backupFileName, jsonContent);
    // 清理不影响已经成功发布的备份；仅删除本应用严格命名的版本。
    try {
      final versions = await listVersions(config);
      for (final old
          in versions.where((entry) => entry.id != version).skip(9)) {
        final response = await _client.request(
          'DELETE',
          _remoteUri(config, fileName: old.id),
          headers: _authHeaders(config),
          deadline: _deadline(15),
        );
        if (response.statusCode != 200 &&
            response.statusCode != 204 &&
            response.statusCode != 404) {
          throw WebDavException('历史版本清理失败', response.statusCode);
        }
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '备份已上传，云端历史清理未完成',
        tag: 'WebDAV',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _put(
    WebDavConfig config,
    String fileName,
    String jsonContent,
  ) async {
    final uri = _remoteUri(config, fileName: fileName);

    final response = await _client.request(
      'PUT',
      uri,
      headers: {
        ..._authHeaders(config),
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: utf8.encode(jsonContent),
      deadline: _deadline(30),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw WebDavException(
        '上传失败 (${response.statusCode})',
        response.statusCode,
      );
    }
  }

  /// 从 WebDAV 服务器下载备份 JSON。
  Future<String> download(WebDavConfig config) async {
    return _downloadFile(config, _backupFileName);
  }

  Future<String> downloadVersion(WebDavConfig config, String versionId) {
    if (!_versionName.hasMatch(versionId)) {
      throw const WebDavException('备份版本标识无效');
    }
    return _downloadFile(config, versionId);
  }

  Future<String> _downloadFile(WebDavConfig config, String fileName) async {
    _validateConfig(config);
    final uri = _remoteUri(config, fileName: fileName);
    final response = await _client.request(
      'GET',
      uri,
      headers: _authHeaders(config),
      deadline: _deadline(30),
    );

    if (response.statusCode == 404) {
      throw const WebDavException('云端暂无备份文件', 404);
    }
    if (response.statusCode != 200) {
      throw WebDavException(
        '下载失败 (${response.statusCode})',
        response.statusCode,
      );
    }

    return utf8.decode(response.bodyBytes);
  }

  Future<List<WebDavBackupVersion>> listVersions(WebDavConfig config) async {
    _validateConfig(config);
    final directory = _remoteUri(config);
    final request = http.Request('PROPFIND', directory)
      ..headers.addAll(_authHeaders(config))
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = _propfindBody;
    final response =
        await _client.sendBounded(request, deadline: _deadline(30));
    final body = await response.stream.bytesToString();
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw WebDavException('历史版本读取失败', response.statusCode);
    }
    // 只取 href，不解释任意远程 XML；严格文件名及 origin/目录边界再次限制。
    final hrefs = RegExp(
      r'<(?:[\w.-]+:)?href\b[^>]*>(.*?)</(?:[\w.-]+:)?href\s*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(body);
    final result = <String, WebDavBackupVersion>{};
    for (final match in hrefs) {
      final href = match.group(1)!.trim().replaceAll('&amp;', '&');
      final reference = Uri.tryParse(href);
      if (reference == null) continue;
      final uri = directory.resolveUri(reference).normalizePath();
      if (!uri.hasAuthority ||
          uri.scheme != directory.scheme ||
          uri.hasQuery ||
          uri.hasFragment) {
        continue;
      }
      if (uri.origin != directory.origin ||
          !uri.path.startsWith(directory.normalizePath().path)) {
        continue;
      }
      final id = uri.pathSegments.lastOrNull;
      if (id == null) continue;
      final version = _versionName.firstMatch(id);
      if (version == null) continue;
      if (uri.path != '${directory.path}$id') continue;
      final micros = int.tryParse(version.group(1)!);
      if (micros == null) continue;
      try {
        result[id] = WebDavBackupVersion(
          id,
          DateTime.fromMicrosecondsSinceEpoch(micros),
        );
      } on ArgumentError {
        continue;
      }
    }
    return result.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 确保远程目录存在，不存在则创建。
  Future<void> _ensureDirectory(WebDavConfig config) async {
    final segments =
        config.normalizedPath.split('/').where((s) => s.isNotEmpty).toList();

    var currentPath = '';
    for (final segment in segments) {
      currentPath += '/$segment';
      final uri = Uri.parse('${config.baseUrl}$currentPath/');

      // 先 PROPFIND 检查是否存在
      final checkReq = http.Request('PROPFIND', uri);
      checkReq.headers.addAll(_authHeaders(config));
      checkReq.headers['Depth'] = '0';
      final checkResp =
          await _client.sendBounded(checkReq, deadline: _deadline(10));
      final checkStatus = checkResp.statusCode;
      await checkResp.stream.drain<void>();

      if (checkStatus == 404) {
        // 不存在，创建
        final mkcolReq = http.Request('MKCOL', uri);
        mkcolReq.headers.addAll(_authHeaders(config));
        final mkcolResp =
            await _client.sendBounded(mkcolReq, deadline: _deadline(10));
        final mkcolStatus = mkcolResp.statusCode;
        await mkcolResp.stream.drain<void>();
        if (mkcolStatus != 201 && mkcolStatus != 405) {
          // 405 = Already exists（部分服务器）
          throw WebDavException(
            '创建目录失败 ($currentPath)',
            mkcolStatus,
          );
        }
      }
    }
  }

  /// 构造 Basic Auth 请求头。
  Map<String, String> _authHeaders(WebDavConfig config) {
    final credentials = base64Encode(
      utf8.encode('${config.username}:${config.password}'),
    );
    return {'Authorization': 'Basic $credentials'};
  }

  void _validateConfig(WebDavConfig config) {
    final urlError = WebDavConfig.validateUrl(config.url);
    if (urlError != null) throw WebDavException(urlError);
    if (config.username.trim().isEmpty) {
      throw const WebDavException('WebDAV 账户不能为空');
    }
    if (config.password.isEmpty) {
      throw const WebDavException('WebDAV 密码不能为空');
    }
    // 路径规则与表单共用 WebDavConfig.validateRemotePath（含空值、编码后的
    // `..`、反斜杠、控制字符），避免两层校验口径不一致。
    final pathError = WebDavConfig.validateRemotePath(config.remotePath);
    if (pathError != null) throw WebDavException(pathError);
  }

  /// 拼接远程 URI，并断言结果没有跳出配置目录。
  ///
  /// 纵深防御：`_validateConfig` 已拦掉编码后的 `..`，这里再对拼接结果做
  /// 点段归一化后比对 origin 与路径前缀。两道都过不去的输入才会发出请求。
  Uri _remoteUri(WebDavConfig config, {String fileName = ''}) {
    final directory = Uri.parse('${config.baseUrl}${config.normalizedPath}');
    final target = Uri.parse(
      '${config.baseUrl}${config.normalizedPath}$fileName',
    );
    final normalized = target.normalizePath();
    if (normalized.origin != directory.origin ||
        !normalized.path.startsWith(directory.normalizePath().path)) {
      throw const WebDavException('WebDAV 远程目录不合法');
    }
    return target;
  }

  /// PROPFIND 请求体。
  static const String _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<D:propfind xmlns:D="DAV:">'
      '<D:prop><D:resourcetype/></D:prop>'
      '</D:propfind>';
}

/// WebDAV 操作异常。
class WebDavException implements Exception {
  const WebDavException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
