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
  /// 测试 WebDAV 连接。
  ///
  /// 向远程根目录发送 PROPFIND 请求，返回是否连通。
  Future<bool> testConnection(WebDavConfig config) async {
    try {
      final uri = Uri.parse('${config.baseUrl}${config.normalizedPath}');
      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(_authHeaders(config));
      request.headers['Depth'] = '0';
      request.headers['Content-Type'] = 'application/xml; charset=utf-8';
      request.body = _propfindBody;

      final response = await http.Client().send(request).timeout(
            const Duration(seconds: 10),
          );
      final statusCode = response.statusCode;
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
    // 先确保目录存在
    await _ensureDirectory(config);

    final uri = Uri.parse(
      '${config.baseUrl}${config.normalizedPath}$_backupFileName',
    );
    final response = await http.put(
      uri,
      headers: {
        ..._authHeaders(config),
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: utf8.encode(jsonContent),
    ).timeout(const Duration(seconds: 30));

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
    final uri = Uri.parse(
      '${config.baseUrl}${config.normalizedPath}$_backupFileName',
    );
    final response = await http.get(
      uri,
      headers: _authHeaders(config),
    ).timeout(const Duration(seconds: 30));

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
    final segments = config.normalizedPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    var currentPath = '';
    for (final segment in segments) {
      currentPath += '/$segment';
      final uri = Uri.parse('${config.baseUrl}$currentPath/');

      // 先 PROPFIND 检查是否存在
      final checkReq = http.Request('PROPFIND', uri);
      checkReq.headers.addAll(_authHeaders(config));
      checkReq.headers['Depth'] = '0';
      final checkResp = await http.Client().send(checkReq).timeout(
            const Duration(seconds: 10),
          );

      if (checkResp.statusCode == 404) {
        // 不存在，创建
        final mkcolReq = http.Request('MKCOL', uri);
        mkcolReq.headers.addAll(_authHeaders(config));
        final mkcolResp = await http.Client().send(mkcolReq).timeout(
              const Duration(seconds: 10),
            );
        if (mkcolResp.statusCode != 201 && mkcolResp.statusCode != 405) {
          // 405 = Already exists（部分服务器）
          throw WebDavException(
            '创建目录失败 ($currentPath)',
            mkcolResp.statusCode,
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
