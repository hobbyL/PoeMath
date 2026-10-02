// lib/core/services/tencent/tc3_signer.dart
//
// 腾讯云 TC3-HMAC-SHA256 通用签名器，供 ASR / TTS 等云接口共用。

import 'dart:convert';

import 'package:crypto/crypto.dart';

const _jsonContentType = 'application/json; charset=utf-8';

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

/// A small, generic TC3-HMAC-SHA256 signer used by Tencent Cloud APIs.
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
    String contentType = _jsonContentType,
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
