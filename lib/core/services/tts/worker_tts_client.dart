// lib/core/services/tts/worker_tts_client.dart
//
// 自建 Cloudflare Worker 语音合成客户端（微软 Edge TTS 代理）。
// 端点契约见 .trellis/tasks/10-03-selfhosted-worker-tts/research/worker-api-contract.md

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:poemath/core/services/tts/tts_models.dart';

const _jsonContentType = 'application/json; charset=utf-8';

/// 自建 Worker TTS 客户端：合成 / 零成本验证 / 音色列表。
///
/// API Key 仅出现在 `Authorization: Bearer` 请求头；异常 message 与
/// `toString()` 不得包含 API Key。
final class WorkerTtsClient {
  WorkerTtsClient({
    http.Client? httpClient,
    Duration synthesizeTimeout = const Duration(seconds: 30),
    Duration probeTimeout = const Duration(seconds: 10),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _synthesizeTimeout = synthesizeTimeout,
        _probeTimeout = probeTimeout;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration _synthesizeTimeout;
  final Duration _probeTimeout;

  static const String _ttsPath = '/api/v1/tts';
  static const String _voicesPath = '/api/v1/voices';

  /// 合法 host 字符（域名 / IPv4 / localhost）。
  ///
  /// `Uri.tryParse` 会把空格等非法字符百分号编码进 host（如 `not a url` →
  /// `not%20a%20url`），因此需要显式字符集校验拦截此类输入。
  static final RegExp _validHostPattern = RegExp(r'^[a-zA-Z0-9.-]+$');

  /// 规范化服务地址：补 `https://` 前缀、去尾斜杠、校验 scheme 与 host。
  ///
  /// 非法输入（无 host、非 http/https scheme）抛出 [FormatException]。
  static Uri normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('服务地址不能为空');
    }
    if (!trimmed.contains('://')) {
      trimmed = 'https://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.host.isEmpty ||
        !_validHostPattern.hasMatch(uri.host)) {
      throw const FormatException('服务地址格式无效');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('服务地址仅支持 http/https');
    }
    return uri;
  }

  /// 合成文本并返回 MP3 音频字节。
  Future<Uint8List> synthesize({
    required WorkerTtsConfig config,
    required String text,
    required String voice,
    required String style,
    required String rate,
  }) async {
    _validateConfig(config);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const WorkerTtsException(
        '合成文本不能为空',
        kind: WorkerTtsErrorKind.request,
      );
    }

    final body = jsonEncode(<String, Object>{
      'text': trimmed,
      'voice': voice,
      'rate': rate,
      'pitch': '0',
      'style': style,
      'format': kWorkerAudioFormat,
    });

    final response = await _send(
      uri: config.base.resolve(_ttsPath),
      body: body,
      apiKey: config.apiKey,
      timeout: _synthesizeTimeout,
      timeoutMessage: '语音合成请求超时',
    );
    return _parseAudioResponse(response);
  }

  /// 验证探测文本：一次两个字的真实合成，成本可忽略。
  static const String _verifyProbeText = '你好';

  /// 验证服务连通性与 API Key：发送一次短文本真实合成。
  ///
  /// 收到有效音频即验证通过（Key 有效 + 服务可用 + 产出音频，完整链路）。
  /// 不要改回「空 text 探测等 400」——那依赖服务端「鉴权先于参数校验」的
  /// 实现细节，服务端版本变化即失效（线上曾对空 text 抛未捕获异常返回
  /// 500）。失败分类沿用 synthesize：401 → authentication、网络 → network、
  /// 其他 → response。
  Future<void> verify(WorkerTtsConfig config) async {
    await synthesize(
      config: config,
      text: _verifyProbeText,
      voice: kDefaultWorkerVoice,
      style: 'general',
      rate: '0',
    );
  }

  /// 拉取中文音色列表（该端点无需认证）。
  Future<List<WorkerTtsVoice>> listVoices(Uri base) async {
    final uri = base.resolve('$_voicesPath?locale=zh-CN');
    http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: const <String, String>{'Accept': _jsonContentType},
      ).timeout(_probeTimeout);
    } on TimeoutException {
      throw const WorkerTtsException(
        '获取在线音色超时',
        kind: WorkerTtsErrorKind.network,
      );
    } on SocketException {
      throw const WorkerTtsException(
        '网络不可用，请检查网络后重试',
        kind: WorkerTtsErrorKind.network,
      );
    } on http.ClientException {
      throw const WorkerTtsException(
        '获取在线音色网络请求失败',
        kind: WorkerTtsErrorKind.network,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkerTtsException(
        '在线音色服务暂时不可用',
        kind: WorkerTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const WorkerTtsException(
        '在线音色返回数据格式无效',
        kind: WorkerTtsErrorKind.response,
      );
    }
    if (decoded is! List<Object?>) {
      throw const WorkerTtsException(
        '在线音色返回数据格式无效',
        kind: WorkerTtsErrorKind.response,
      );
    }

    final voices = <WorkerTtsVoice>[];
    for (final item in decoded) {
      if (item is! Map<Object?, Object?>) continue;
      final shortName = item['short_name']?.toString();
      if (shortName == null || shortName.isEmpty) continue;
      final styleList = item['style_list'];
      voices.add(
        WorkerTtsVoice(
          shortName: shortName,
          localName: item['local_name']?.toString() ?? shortName,
          gender: item['gender']?.toString() ?? '',
          styleList: styleList is List<Object?>
              ? styleList.map((e) => e.toString()).toList()
              : const <String>[],
        ),
      );
    }
    return voices;
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  // ============ 内部 ============

  void _validateConfig(WorkerTtsConfig config) {
    if (!config.isComplete) {
      throw const WorkerTtsException(
        '语音服务地址或 API Key 未填写完整',
        kind: WorkerTtsErrorKind.authentication,
      );
    }
  }

  Future<http.Response> _send({
    required Uri uri,
    required String body,
    required String apiKey,
    required Duration timeout,
    required String timeoutMessage,
  }) async {
    try {
      return await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': _jsonContentType,
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw WorkerTtsException(
        timeoutMessage,
        kind: WorkerTtsErrorKind.network,
      );
    } on SocketException {
      throw const WorkerTtsException(
        '网络不可用，请检查网络后重试',
        kind: WorkerTtsErrorKind.network,
      );
    } on http.ClientException {
      throw const WorkerTtsException(
        '网络请求失败',
        kind: WorkerTtsErrorKind.network,
      );
    }
  }

  Uint8List _parseAudioResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw WorkerTtsException(
        _messageForStatus(response),
        kind: WorkerTtsErrorKind.authentication,
        statusCode: 401,
      );
    }
    if (response.statusCode == 400) {
      throw WorkerTtsException(
        _messageForStatus(response),
        kind: WorkerTtsErrorKind.request,
        statusCode: 400,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkerTtsException(
        '语音合成服务暂时不可用',
        kind: WorkerTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('audio')) {
      throw WorkerTtsException(
        '语音服务未返回有效音频',
        kind: WorkerTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    if (bytes.isEmpty) {
      throw WorkerTtsException(
        '语音服务未返回有效音频',
        kind: WorkerTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    return bytes;
  }

  /// 服务端 JSON 错误体 `{"error": msg}` 的 message 透传（不含 API Key）。
  static String _messageForStatus(http.Response response) {
    if (response.statusCode == 401) {
      return 'API Key 无效或未授权，请检查后重试';
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.isNotEmpty) return error;
      }
    } on FormatException {
      // fallthrough 到默认消息
    }
    return '语音服务请求失败（HTTP ${response.statusCode}）';
  }
}
