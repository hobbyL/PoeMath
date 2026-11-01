import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:poemath/core/services/bounded_http_client.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tencent/tc3_signer.dart';

enum TencentAppIdErrorKind { authentication, network, response }

final class TencentAppIdException extends SpeechRecognitionException {
  const TencentAppIdException(super.message, {required this.kind, this.code});

  final TencentAppIdErrorKind kind;
  final String? code;
}

/// Resolves account APPID without persisting account metadata or credentials.
class TencentAppIdClient {
  TencentAppIdClient({
    http.Client? httpClient,
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 12),
  })  : _httpClient = BoundedHttpClient(
          httpClient ?? http.Client(),
          timeout: timeout,
          maxResponseBytes: 64 * 1024,
        ),
        _ownsHttpClient = httpClient == null,
        _clock = clock ?? DateTime.now,
        _timeout = timeout;

  final BoundedHttpClient _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _clock;
  final Duration _timeout;
  String? _cachedFingerprint;
  String? _cachedAppId;

  Future<String> resolve({
    required TencentAsrCredentials credentials,
    SpeechRecognitionCancelToken? cancelToken,
  }) async {
    cancelToken?.check();
    if (!credentials.isComplete) {
      throw const TencentAppIdException(
        '请先填写腾讯云 SecretId 和 SecretKey',
        kind: TencentAppIdErrorKind.authentication,
      );
    }
    final credentialIdentity = jsonEncode(<String>[
      credentials.secretId,
      credentials.secretKey,
    ]);
    final fingerprint =
        sha256.convert(utf8.encode(credentialIdentity)).toString();
    if (_cachedFingerprint == fingerprint && _cachedAppId != null) {
      return _cachedAppId!;
    }

    const host = 'cam.tencentcloudapi.com';
    const action = 'GetUserAppId';
    const version = '2019-01-16';
    const body = '{}';
    final timestamp = _clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    final signature = TencentTc3Signer.sign(
      secretId: credentials.secretId,
      secretKey: credentials.secretKey,
      service: 'cam',
      host: host,
      action: action,
      version: version,
      timestamp: timestamp,
      body: body,
    );
    final request = http.AbortableRequest(
      'POST',
      Uri.https(host),
      abortTrigger: cancelToken?.abortTrigger,
    )
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': signature.authorization,
        'Content-Type': 'application/json; charset=utf-8',
        'Host': host,
        'X-TC-Action': action,
        'X-TC-Version': version,
        'X-TC-Timestamp': '$timestamp',
      })
      ..body = body;

    late final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _httpClient.sendBounded(request, deadline: _timeout),
      );
    } on http.RequestAbortedException {
      cancelToken?.check();
      throw const TencentAppIdException(
        '腾讯云 APPID 查询已中止，请重试',
        kind: TencentAppIdErrorKind.network,
      );
    } on TimeoutException {
      cancelToken?.check();
      throw const TencentAppIdException(
        '获取腾讯云 APPID 超时，请检查网络后重试',
        kind: TencentAppIdErrorKind.network,
      );
    } on SocketException {
      cancelToken?.check();
      throw const TencentAppIdException(
        '获取腾讯云 APPID 网络失败，请检查网络后重试',
        kind: TencentAppIdErrorKind.network,
      );
    } on http.ClientException {
      cancelToken?.check();
      throw const TencentAppIdException(
        '获取腾讯云 APPID 网络失败，请检查网络后重试',
        kind: TencentAppIdErrorKind.network,
      );
    } on FormatException {
      cancelToken?.check();
      throw const TencentAppIdException(
        '腾讯云 APPID 响应无效，请在高级设置中填写 APPID',
        kind: TencentAppIdErrorKind.response,
      );
    }
    cancelToken?.check();
    final appId = _parseResponse(response);
    _cachedFingerprint = fingerprint;
    _cachedAppId = appId;
    return appId;
  }

  String _parseResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const TencentAppIdException(
        '腾讯云 APPID 响应无效，请在高级设置中填写 APPID',
        kind: TencentAppIdErrorKind.response,
      );
    }
    final payload =
        decoded is Map<String, dynamic> ? decoded['Response'] : null;
    if (payload is! Map<String, dynamic>) {
      throw const TencentAppIdException(
        '腾讯云 APPID 响应无效，请在高级设置中填写 APPID',
        kind: TencentAppIdErrorKind.response,
      );
    }
    final error = payload['Error'];
    if (error is Map<String, dynamic>) {
      final rawCode = error['Code'];
      final code = rawCode is String ? rawCode : null;
      final authentication = code?.startsWith('AuthFailure') == true ||
          code?.startsWith('UnauthorizedOperation') == true;
      throw TencentAppIdException(
        authentication
            ? '腾讯云密钥无效或无权查询 APPID，请检查密钥或在高级设置中填写 APPID'
            : '自动获取腾讯云 APPID 失败，请在高级设置中填写 APPID',
        kind: authentication
            ? TencentAppIdErrorKind.authentication
            : TencentAppIdErrorKind.response,
        code: code,
      );
    }
    final appId = payload['AppId'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        appId is! int ||
        appId <= 0) {
      throw const TencentAppIdException(
        '腾讯云未返回有效 APPID，请在高级设置中填写 APPID',
        kind: TencentAppIdErrorKind.response,
      );
    }
    // Uin / OwnerUin are different identifiers and must never be used as APPID.
    return '$appId';
  }

  void close() {
    _cachedFingerprint = null;
    _cachedAppId = null;
    _httpClient.close();
    if (_ownsHttpClient) _httpClient.inner.close();
  }
}
