// lib/data/models/webdav_config.dart
//
// 层级：data/models
// 职责：WebDAV 同步配置数据模型。
//       存储在 settings box 中（JSON 序列化），不使用 Hive adapter。

import 'dart:convert';

/// WebDAV 同步配置。
class WebDavConfig {
  WebDavConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    this.remotePath = '/poemath/',
  });

  /// 唯一标识（时间戳生成）。
  final String id;

  /// 显示名称（用户自定义，如"家里 NAS"）。
  final String name;

  /// WebDAV 服务器地址（含协议，如 https://dav.example.com）。
  final String url;

  /// 账户名。
  final String username;

  /// 密码。
  final String password;

  /// 远程根目录，默认 `/poemath/`。
  final String remotePath;

  /// 校验 WebDAV 地址。
  ///
  /// WebDAV 使用 Basic Auth，公开发布版本只允许 HTTPS，避免凭据以明文
  /// 传输；账号和密码必须通过安全存储/请求头提供，不得嵌入 URL。
  static String? validateUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '请输入服务器地址';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return '请输入有效的服务器地址';
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return '服务器地址必须使用 HTTPS，不支持明文 HTTP';
    }
    if (uri.userInfo.isNotEmpty) {
      return '请不要在地址中包含账号或密码';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return '服务器地址不能包含 query 或 fragment';
    }
    return null;
  }

  /// 校验远程目录。
  ///
  /// `remotePath` 会被直接拼进请求 URL（`baseUrl + normalizedPath + 文件名`），
  /// 而服务端在路由前会做百分号解码，所以只检查字面 `..` 会被
  /// `%2e%2e`、`%252e%252e`、`..%2f` 之类的编码绕过，拿到越界的读写路径。
  /// 这里先反复解码到稳定再逐段比对，并拒绝会改变 URL 结构的字符。
  ///
  /// 返回 `null` 表示合法；否则返回面向用户的中文错误。
  static String? validateRemotePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '请输入远程目录';

    final decoded = _fullyDecodePath(trimmed);
    if (decoded == null) return '远程目录包含无法识别的转义字符';

    // `\` 在部分 WebDAV 服务端等价于 `/`；`?` 与 `#` 会截断路径，
    // 让备份文件名落进 query/fragment。
    if (decoded.contains(r'\')) return '远程目录不能包含反斜杠';
    if (decoded.contains('?') || decoded.contains('#')) {
      return '远程目录不能包含 ? 或 #';
    }
    if (decoded.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      return '远程目录不能包含控制字符';
    }

    final segments = decoded.split('/');
    if (segments.contains('..') || segments.contains('.')) {
      return '远程目录不能包含 . 或 .. 路径段';
    }
    return null;
  }

  /// 反复百分号解码直到不再变化。
  ///
  /// 非法转义（如 `%zz`）或超过 [_maxDecodePasses] 轮仍在变化都返回 `null`：
  /// 这类输入在不同服务端的解码次数不一致，无法静态判定安全，直接拒绝。
  static String? _fullyDecodePath(String value) {
    var current = value;
    for (var pass = 0; pass < _maxDecodePasses; pass++) {
      if (!current.contains('%')) return current;
      final String next;
      try {
        next = Uri.decodeComponent(current);
      } on ArgumentError {
        return null;
      } on FormatException {
        return null;
      }
      if (next == current) return current;
      current = next;
    }
    return null;
  }

  /// 解码轮数上限，防解码炸弹。
  static const int _maxDecodePasses = 4;

  /// 规范化后的基础 URL：去尾 `/`。
  String get baseUrl {
    final trimmed = url.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// 规范化后的远程路径：确保首尾 `/`。
  String get normalizedPath {
    var p = remotePath.trim();
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    return p;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'remotePath': remotePath,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) => WebDavConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        remotePath: json['remotePath'] as String? ?? '/poemath/',
      );

  /// 将配置列表序列化为 JSON 字符串。
  static String encodeList(List<WebDavConfig> configs) {
    return jsonEncode(configs.map((c) => c.toJson()).toList());
  }

  /// 从 JSON 字符串反序列化配置列表。
  static List<WebDavConfig> decodeList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List<dynamic>;
      return list
          .map((e) => WebDavConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception {
      return [];
    }
  }
}
