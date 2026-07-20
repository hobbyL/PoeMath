// lib/core/services/webdav_service.dart
//
// 层级：core/services
// 职责：WebDAV 客户端服务 — 通过 WebDAV 协议上传/下载备份文件。
//       使用 http 包发送自定义 HTTP 方法（PROPFIND/MKCOL/PUT/GET）。

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:poemath/data/models/webdav_config.dart';

/// WebDAV 备份文件名。
const String _backupFileName = 'poemath_backup.json';

/// WebDAV 客户端服务。
class WebDavService {
  WebDavService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 释放 HTTP 连接池。
  void dispose() => _client.close();

  /// 测试 WebDAV 连接。
  ///
  /// 向远程根目录发送 PROPFIND 请求，返回是否连通。
  Future<bool> testConnection(WebDavConfig config) async {
    _validateConfig(config);
    try {
      final uri = Uri.parse('${config.baseUrl}${config.normalizedPath}');
      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(_authHeaders(config));
      request.headers['Depth'] = '0';
      request.headers['Content-Type'] = 'application/xml; charset=utf-8';
      request.body = _propfindBody;

      final response = await _client.send(request).timeout(
            const Duration(seconds: 10),
          );
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

    final uri = Uri.parse(
      '${config.baseUrl}${config.normalizedPath}$_backupFileName',
    );
    final response = await _client
        .put(
          uri,
          headers: {
            ..._authHeaders(config),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: utf8.encode(jsonContent),
        )
        .timeout(const Duration(seconds: 30));

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
    _validateConfig(config);
    final uri = Uri.parse(
      '${config.baseUrl}${config.normalizedPath}$_backupFileName',
    );
    final response = await _client
        .get(
          uri,
          headers: _authHeaders(config),
        )
        .timeout(const Duration(seconds: 30));

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
      final checkResp = await _client.send(checkReq).timeout(
            const Duration(seconds: 10),
          );
      final checkStatus = checkResp.statusCode;
      await checkResp.stream.drain<void>();

      if (checkStatus == 404) {
        // 不存在，创建
        final mkcolReq = http.Request('MKCOL', uri);
        mkcolReq.headers.addAll(_authHeaders(config));
        final mkcolResp = await _client.send(mkcolReq).timeout(
              const Duration(seconds: 10),
            );
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
    if (config.remotePath.trim().isEmpty) {
      throw const WebDavException('WebDAV 远程目录不能为空');
    }
    final segments = config.normalizedPath.split('/');
    if (segments.contains('..')) {
      throw const WebDavException('WebDAV 远程目录不能包含 ..');
    }
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
