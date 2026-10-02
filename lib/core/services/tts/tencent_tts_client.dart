// lib/core/services/tts/tencent_tts_client.dart
//
// 腾讯云基础语音合成客户端：TextToVoice（整段合成，mp3 返回）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tencent/tc3_signer.dart';
import 'package:poemath/core/services/tts/tts_models.dart';

const _ttsContentType = 'application/json; charset=utf-8';

/// Tencent Cloud TextToVoice client.
///
/// 复用与 ASR 相同的 TC3 签名器与账户凭据；服务开通状态独立于 ASR。
final class TencentTtsClient {
  TencentTtsClient({
    http.Client? httpClient,
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 15),
    Uri? endpoint,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _clock = clock ?? DateTime.now,
        _timeout = timeout,
        _endpoint =
            endpoint ?? Uri(scheme: 'https', host: 'tts.tencentcloudapi.com');

  static const String service = 'tts';
  static const String action = 'TextToVoice';
  static const String version = '2019-08-23';

  /// 单次合成文本上限：中文 150 个汉字（全角标点计 1），
  /// 英文 500 个字母（半角标点计 1）。加权计数拦截。
  static const int maxChineseChars = 150;
  static const int maxAsciiLetters = 500;
  static const double _asciiWeight = maxChineseChars / maxAsciiLetters;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _clock;
  final Duration _timeout;
  final Uri _endpoint;
  final Random _random = Random();

  /// 合成文本并返回音频字节（默认 mp3）。
  Future<Uint8List> synthesize({
    required String text,
    required TencentAsrCredentials credentials,
    required int voiceType,
    double speed = 1.0,
    String codec = 'mp3',
  }) async {
    if (!credentials.isComplete) {
      throw const TencentTtsException(
        '腾讯云凭据未填写完整',
        kind: TencentTtsErrorKind.authentication,
      );
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const TencentTtsException(
        '合成文本为空',
        kind: TencentTtsErrorKind.request,
      );
    }
    final weightedLength = _weightedLength(trimmed);
    if (weightedLength > maxChineseChars) {
      throw const TencentTtsException(
        '单次合成不能超过 150 个汉字，请分行朗读',
        kind: TencentTtsErrorKind.request,
      );
    }

    final body = jsonEncode(<String, Object>{
      'Text': trimmed,
      'SessionId': _newSessionId(),
      'Volume': 0,
      'Speed': speed,
      'VoiceType': voiceType,
      'Codec': codec,
    });
    final now = _clock().toUtc();
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    final host = _endpoint.host;
    final signature = TencentTc3Signer.sign(
      secretId: credentials.secretId,
      secretKey: credentials.secretKey,
      service: service,
      host: host,
      action: action,
      version: version,
      timestamp: timestamp,
      body: body,
    );

    final response = await _send(
      body: body,
      signature: signature,
      timestamp: timestamp,
      host: host,
    );
    return _parseResponse(response);
  }

  /// 全角字符计 1，半角字符按 150/500 加权折算。
  static double _weightedLength(String text) {
    var weight = 0.0;
    for (final codeUnit in text.codeUnits) {
      // ASCII 范围视为半角，其余（含全角标点、汉字）计 1。
      if (codeUnit < 0x80) {
        weight += _asciiWeight;
      } else {
        weight += 1;
      }
    }
    return weight;
  }

  String _newSessionId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = List<String>.generate(
      8,
      (_) => _random.nextInt(36).toRadixString(36),
    ).join();
    return 'poemath-$micros-$random';
  }

  Future<http.Response> _send({
    required String body,
    required TencentTc3Signature signature,
    required int timestamp,
    required String host,
  }) async {
    try {
      return await _httpClient
          .post(
            _endpoint,
            headers: <String, String>{
              'Authorization': signature.authorization,
              'Content-Type': _ttsContentType,
              'Host': host,
              'X-TC-Action': action,
              'X-TC-Version': version,
              'X-TC-Timestamp': '$timestamp',
            },
            body: body,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const TencentTtsException(
        '腾讯云合成请求超时',
        kind: TencentTtsErrorKind.network,
      );
    } on SocketException {
      throw const TencentTtsException(
        '网络不可用，请检查网络后重试',
        kind: TencentTtsErrorKind.network,
      );
    } on http.ClientException {
      throw const TencentTtsException(
        '腾讯云合成网络请求失败',
        kind: TencentTtsErrorKind.network,
      );
    }
  }

  Uint8List _parseResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw TencentTtsException(
        '腾讯云返回数据格式无效',
        kind: TencentTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw TencentTtsException(
        '腾讯云返回数据格式无效',
        kind: TencentTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }

    final responseBody = decoded['Response'];
    if (responseBody is! Map<String, dynamic>) {
      throw TencentTtsException(
        '腾讯云返回数据格式无效',
        kind: TencentTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    final error = responseBody['Error'];
    if (error is Map<String, dynamic>) {
      final rawCode = error['Code'];
      final code = rawCode is String ? rawCode : null;
      throw TencentTtsException(
        _messageForErrorCode(code),
        kind: _kindForErrorCode(code),
        code: code,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TencentTtsException(
        '腾讯云合成服务暂时不可用',
        kind: TencentTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }

    final audio = responseBody['Audio'];
    if (audio is! String || audio.isEmpty) {
      throw TencentTtsException(
        '腾讯云未返回有效合成音频',
        kind: TencentTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    try {
      final bytes = base64Decode(audio);
      if (bytes.isEmpty) {
        throw const TencentTtsException(
          '腾讯云未返回有效合成音频',
          kind: TencentTtsErrorKind.response,
        );
      }
      return bytes;
    } on FormatException {
      throw TencentTtsException(
        '腾讯云返回音频数据无效',
        kind: TencentTtsErrorKind.response,
        statusCode: response.statusCode,
      );
    }
  }

  static TencentTtsErrorKind _kindForErrorCode(String? code) {
    if (code == null) return TencentTtsErrorKind.response;
    if (code.startsWith('AuthFailure') ||
        code.startsWith('UnsupportedOperation.Authorization')) {
      return TencentTtsErrorKind.authentication;
    }
    if (code == 'UnsupportedOperation.ServerNotOpen' ||
        code == 'InvalidParameterValue.AppIdNotRegistered') {
      return TencentTtsErrorKind.serviceNotEnabled;
    }
    if (code.contains('NoFree') ||
        code == 'UnsupportedOperation.PkgExhausted' ||
        code == 'UnsupportedOperation.AccountArrears') {
      return TencentTtsErrorKind.quota;
    }
    if (code.startsWith('InvalidParameter') || code.startsWith('Request')) {
      return TencentTtsErrorKind.request;
    }
    return TencentTtsErrorKind.response;
  }

  static String _messageForErrorCode(String? code) {
    final kind = _kindForErrorCode(code);
    return switch (kind) {
      TencentTtsErrorKind.authentication => '腾讯云密钥无效或没有合成权限',
      TencentTtsErrorKind.quota => '腾讯云语音合成额度已用尽或账户欠费',
      TencentTtsErrorKind.serviceNotEnabled => '请在腾讯云控制台开通语音合成服务',
      TencentTtsErrorKind.request => '腾讯云拒绝了合成请求',
      TencentTtsErrorKind.network => '腾讯云合成网络请求失败',
      TencentTtsErrorKind.response => '腾讯云合成失败',
    };
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
