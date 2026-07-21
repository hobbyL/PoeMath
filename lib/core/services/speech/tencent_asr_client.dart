// lib/core/services/speech/tencent_asr_client.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:poemath/core/services/speech/speech_recognition_models.dart';

const _tencentAsrContentType = 'application/json; charset=utf-8';

final class TencentTc3Signature {
  const TencentTc3Signature({
    required this.authorization,
    required this.canonicalRequest,
    required this.stringToSign,
    required this.signature,
    required this.date,
  });

  final String authorization;
  final String canonicalRequest;
  final String stringToSign;
  final String signature;
  final String date;
}

/// A small, generic TC3-HMAC-SHA256 signer used by Tencent ASR.
final class TencentTc3Signer {
  const TencentTc3Signer._();

  static TencentTc3Signature sign({
    required String secretId,
    required String secretKey,
    required String service,
    required String host,
    required String action,
    required String version,
    required int timestamp,
    required String body,
    String contentType = _tencentAsrContentType,
  }) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    );
    final dateString = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    const algorithm = 'TC3-HMAC-SHA256';
    const signedHeaders = 'content-type;host;x-tc-action';
    final canonicalHeaders =
        'content-type:${contentType.toLowerCase().trim()}\n'
        'host:${host.toLowerCase().trim()}\n'
        'x-tc-action:${action.toLowerCase().trim()}\n';
    final hashedBody = _sha256Hex(body);
    final canonicalRequest =
        'POST\n/\n\n$canonicalHeaders\n$signedHeaders\n$hashedBody';
    final credentialScope = '$dateString/$service/tc3_request';
    final hashedCanonicalRequest = _sha256Hex(canonicalRequest);
    final stringToSign =
        '$algorithm\n$timestamp\n$credentialScope\n$hashedCanonicalRequest';

    final secretDate = _hmac(
      utf8.encode('TC3$secretKey'),
      dateString,
    );
    final secretService = _hmac(secretDate, service);
    final secretSigning = _hmac(secretService, 'tc3_request');
    final signature = _hmacHex(secretSigning, stringToSign);
    final authorization = '$algorithm Credential=$secretId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    return TencentTc3Signature(
      authorization: authorization,
      canonicalRequest: canonicalRequest,
      stringToSign: stringToSign,
      signature: signature,
      date: dateString,
    );
  }

  static String _sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static List<int> _hmac(List<int> key, String value) {
    return Hmac(sha256, key).convert(utf8.encode(value)).bytes;
  }

  static String _hmacHex(List<int> key, String value) {
    return Hmac(sha256, key).convert(utf8.encode(value)).toString();
  }
}

enum TencentAsrErrorKind { authentication, quota, request, network, response }

final class TencentAsrException extends SpeechRecognitionException {
  const TencentAsrException(
    super.message, {
    required this.kind,
    this.code,
    this.statusCode,
  });

  final TencentAsrErrorKind kind;
  final String? code;
  final int? statusCode;
}

/// Tencent Cloud SentenceRecognition client.
final class TencentAsrClient {
  TencentAsrClient({
    http.Client? httpClient,
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 15),
    Uri? endpoint,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _clock = clock ?? DateTime.now,
        _timeout = timeout,
        _endpoint =
            endpoint ?? Uri(scheme: 'https', host: 'asr.tencentcloudapi.com');

  static const String service = 'asr';
  static const String action = 'SentenceRecognition';
  static const String version = '2019-06-14';
  static const int sampleRate = 16000;
  static const int maxSeconds = 60;
  static const int maxRawBytes = sampleRate * 2 * maxSeconds;
  static const int maxBase64Bytes = 3 * 1024 * 1024;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _clock;
  final Duration _timeout;
  final Uri _endpoint;

  Future<String> recognizePcm16({
    required Uint8List pcmBytes,
    required TencentAsrCredentials credentials,
  }) async {
    if (!credentials.isComplete) {
      throw const TencentAsrException(
        '腾讯云凭据未填写完整',
        kind: TencentAsrErrorKind.authentication,
      );
    }
    if (pcmBytes.isEmpty || pcmBytes.length.isOdd) {
      throw const TencentAsrException(
        '录音数据为空或格式不完整',
        kind: TencentAsrErrorKind.request,
      );
    }
    if (pcmBytes.length > maxRawBytes) {
      throw const TencentAsrException(
        '录音不能超过 60 秒',
        kind: TencentAsrErrorKind.request,
      );
    }

    final encoded = base64Encode(pcmBytes);
    if (encoded.length > maxBase64Bytes) {
      throw const TencentAsrException(
        '录音文件超过腾讯云 3 MiB 限制',
        kind: TencentAsrErrorKind.request,
      );
    }

    final body = jsonEncode(<String, Object>{
      'EngSerViceType': '16k_zh',
      'SourceType': 1,
      'VoiceFormat': 'pcm',
      'Data': encoded,
      'DataLen': pcmBytes.length,
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
              'Content-Type': _tencentAsrContentType,
              'Host': host,
              'X-TC-Action': action,
              'X-TC-Version': version,
              'X-TC-Timestamp': '$timestamp',
            },
            body: body,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const TencentAsrException(
        '腾讯云识别请求超时',
        kind: TencentAsrErrorKind.network,
      );
    } on SocketException {
      throw const TencentAsrException(
        '网络不可用，已使用离线识别',
        kind: TencentAsrErrorKind.network,
      );
    } on http.ClientException {
      throw const TencentAsrException(
        '腾讯云识别网络请求失败',
        kind: TencentAsrErrorKind.network,
      );
    }
  }

  String _parseResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw TencentAsrException(
        '腾讯云返回数据格式无效',
        kind: TencentAsrErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw TencentAsrException(
        '腾讯云返回数据格式无效',
        kind: TencentAsrErrorKind.response,
        statusCode: response.statusCode,
      );
    }

    final responseBody = decoded['Response'];
    if (responseBody is! Map<String, dynamic>) {
      throw TencentAsrException(
        '腾讯云返回数据格式无效',
        kind: TencentAsrErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    final error = responseBody['Error'];
    if (error is Map<String, dynamic>) {
      final rawCode = error['Code'];
      final code = rawCode is String ? rawCode : null;
      throw TencentAsrException(
        _messageForErrorCode(code),
        kind: _kindForErrorCode(code),
        code: code,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TencentAsrException(
        '腾讯云识别服务暂时不可用',
        kind: TencentAsrErrorKind.response,
        statusCode: response.statusCode,
      );
    }

    final result = responseBody['Result'];
    if (result is! String || result.trim().isEmpty) {
      throw TencentAsrException(
        '腾讯云未返回有效识别文字',
        kind: TencentAsrErrorKind.response,
        statusCode: response.statusCode,
      );
    }
    return result.trim();
  }

  static TencentAsrErrorKind _kindForErrorCode(String? code) {
    if (code == null) return TencentAsrErrorKind.response;
    if (code.startsWith('AuthFailure')) {
      return TencentAsrErrorKind.authentication;
    }
    if (code.contains('Limit') || code.contains('NoFree')) {
      return TencentAsrErrorKind.quota;
    }
    if (code.startsWith('InvalidParameter') || code.startsWith('Request')) {
      return TencentAsrErrorKind.request;
    }
    return TencentAsrErrorKind.response;
  }

  static String _messageForErrorCode(String? code) {
    final kind = _kindForErrorCode(code);
    return switch (kind) {
      TencentAsrErrorKind.authentication => '腾讯云密钥无效或没有识别权限',
      TencentAsrErrorKind.quota => '腾讯云识别额度暂不可用',
      TencentAsrErrorKind.request => '腾讯云拒绝了录音请求',
      TencentAsrErrorKind.network => '腾讯云识别网络请求失败',
      TencentAsrErrorKind.response => '腾讯云识别失败',
    };
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
