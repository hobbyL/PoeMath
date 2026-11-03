// lib/core/services/speech/tencent_realtime_asr_client.dart
//
// 腾讯云实时语音识别 WebSocket 客户端。实时接口使用 HMAC-SHA1 URL 签名，
// 与 SentenceRecognition 的 TC3 HTTP 签名不是同一套协议。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tencent/tencent_app_id_client.dart';

enum TencentRealtimeErrorKind { authentication, quota, network, response }

final class TencentRealtimeAsrException extends SpeechRecognitionException {
  const TencentRealtimeAsrException(
    super.message, {
    required this.kind,
    this.code,
  });

  final TencentRealtimeErrorKind kind;
  final int? code;
}

final class TencentRealtimeAsrClient {
  TencentRealtimeAsrClient({
    DateTime Function()? clock,
    Random? random,
    this._timeout = const Duration(seconds: 12),
    CloudUsageService? usage,
    TencentAppIdClient? appIdClient,
    Future<WebSocket> Function(Uri)? connectSocket,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure(),
        _usage = usage ?? CloudUsageService.instance,
        _appIdClient = appIdClient ?? TencentAppIdClient(),
        _ownsAppIdClient = appIdClient == null,
        _connectSocket = connectSocket ?? _openSocket;

  final DateTime Function() _clock;
  final Random _random;
  final Duration _timeout;
  final CloudUsageService _usage;
  final TencentAppIdClient _appIdClient;
  final bool _ownsAppIdClient;
  final Future<WebSocket> Function(Uri) _connectSocket;

  static Future<WebSocket> _openSocket(Uri uri) =>
      WebSocket.connect(uri.toString());

  Future<TencentRealtimeAsrSession> connect({
    required TencentAsrCredentials credentials,
    void Function(String text, {required bool stable})? onText,
    SpeechRecognitionCancelToken? cancelToken,
  }) async {
    cancelToken?.check();
    if (!credentials.isComplete) {
      throw const TencentRealtimeAsrException(
        '请先填写腾讯云 SecretId 和 SecretKey',
        kind: TencentRealtimeErrorKind.authentication,
      );
    }
    final configuredAppId = credentials.appId.trim();
    if (configuredAppId.isNotEmpty &&
        !RegExp(r'^[1-9]\d*$').hasMatch(configuredAppId)) {
      throw const TencentRealtimeAsrException(
        '腾讯云 APPID 应为账号信息页中的数字',
        kind: TencentRealtimeErrorKind.authentication,
      );
    }
    try {
      final reservation = _usage.reserve(
        CloudUsageKind.asr,
        check: cancelToken?.check,
      );
      await (cancelToken?.wait(reservation) ?? reservation);
    } on CloudQuotaExceededException catch (error) {
      cancelToken?.check();
      throw TencentRealtimeAsrException(
        error.message,
        kind: TencentRealtimeErrorKind.quota,
        code: -1,
      );
    }
    cancelToken?.check();
    late final String appId;
    try {
      appId = configuredAppId.isNotEmpty
          ? configuredAppId
          : await _appIdClient.resolve(
              credentials: credentials,
              cancelToken: cancelToken,
            );
    } on TencentAppIdException catch (error) {
      throw TencentRealtimeAsrException(
        error.message,
        kind: switch (error.kind) {
          TencentAppIdErrorKind.authentication =>
            TencentRealtimeErrorKind.authentication,
          TencentAppIdErrorKind.network => TencentRealtimeErrorKind.network,
          TencentAppIdErrorKind.response => TencentRealtimeErrorKind.response,
        },
      );
    }
    cancelToken?.check();
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    final nonce = _random.nextInt(0x7fffffff) + 1;
    final expired = now + 3600;
    final voiceId = _voiceId();
    final query = <String, String>{
      'engine_model_type': '16k_zh',
      'expired': '$expired',
      'filter_empty_result': '1',
      'filter_modal': '0',
      'filter_punc': '0',
      'max_speak_time': '60000',
      'needvad': '1',
      'nonce': '$nonce',
      'secretid': credentials.secretId,
      'timestamp': '$now',
      'voice_format': '1',
      'voice_id': voiceId,
    };
    final signatureBase = 'asr.cloud.tencent.com/asr/v2/$appId?'
        '${_canonicalQuery(query)}';
    final signature = base64Encode(
      Hmac(sha1, utf8.encode(credentials.secretKey))
          .convert(utf8.encode(signatureBase))
          .bytes,
    );
    query['signature'] = signature;
    final uri = Uri(
      scheme: 'wss',
      host: 'asr.cloud.tencent.com',
      pathSegments: <String>['asr', 'v2', appId],
      queryParameters: query,
    );

    late final WebSocket socket;
    try {
      final connecting = _connectSocket(uri).then((socket) {
        if (cancelToken?.isCancelled ?? false) {
          unawaited(socket.close(WebSocketStatus.goingAway));
          throw const SpeechRecognitionCancelled();
        }
        return socket;
      }).timeout(_timeout);
      socket = await (cancelToken?.wait(connecting) ?? connecting);
    } on TimeoutException {
      cancelToken?.check();
      throw const TencentRealtimeAsrException(
        '腾讯云实时识别连接超时',
        kind: TencentRealtimeErrorKind.network,
      );
    } on SocketException {
      cancelToken?.check();
      throw const TencentRealtimeAsrException(
        '腾讯云实时识别网络不可用',
        kind: TencentRealtimeErrorKind.network,
      );
    } on HandshakeException {
      cancelToken?.check();
      throw const TencentRealtimeAsrException(
        '腾讯云实时识别安全连接失败，请检查网络后重试',
        kind: TencentRealtimeErrorKind.network,
      );
    } on WebSocketException {
      cancelToken?.check();
      throw const TencentRealtimeAsrException(
        '腾讯云实时识别连接失败，请检查网络后重试',
        kind: TencentRealtimeErrorKind.network,
      );
    }

    final ready = Completer<void>();
    final finished = Completer<void>();
    // 握手期间可能同时失败；保留 end() 的错误，但不留下尚未被等待的错误。
    unawaited(finished.future.then<void>((_) {}, onError: (Object _) {}));
    TencentRealtimeAsrException? failure;
    var finalText = '';
    final sentenceTexts = <int, String>{};
    StreamSubscription<Object?>? subscription;

    void handle(Object? message) {
      if (message is! String) return;
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(message);
        if (decoded is! Map<String, dynamic>) return;
        json = decoded;
      } on Object {
        return;
      }
      final code = (json['code'] as num?)?.toInt();
      if (code != null && code != 0) {
        failure = TencentRealtimeAsrException(
          _messageForCode(code),
          kind: _kindForCode(code),
          code: code,
        );
        if (!ready.isCompleted) ready.completeError(failure!);
        if (!finished.isCompleted) finished.completeError(failure!);
        return;
      }
      if (!ready.isCompleted && json['voice_id'] != null) ready.complete();
      final result = json['result'];
      if (result is Map<String, dynamic>) {
        final text = result['voice_text_str'];
        if (text is String) {
          final index = (result['index'] as num?)?.toInt() ?? 0;
          sentenceTexts[index] = text;
          final indices = sentenceTexts.keys.toList()..sort();
          finalText = indices.map((item) => sentenceTexts[item]!).join();
          onText?.call(
            finalText,
            stable: (result['slice_type'] as num?)?.toInt() == 2,
          );
        }
      }
      if (json['final'] == 1 && !finished.isCompleted) finished.complete();
    }

    subscription = socket.listen(
      handle,
      onError: (Object error, StackTrace stack) {
        failure ??= const TencentRealtimeAsrException(
          '腾讯云实时识别连接中断',
          kind: TencentRealtimeErrorKind.network,
        );
        if (!ready.isCompleted) ready.completeError(failure!);
        if (!finished.isCompleted) finished.completeError(failure!);
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            const TencentRealtimeAsrException(
              '腾讯云实时识别握手失败',
              kind: TencentRealtimeErrorKind.authentication,
            ),
          );
        }
        if (!finished.isCompleted) finished.complete();
      },
    );

    try {
      final handshake = ready.future.timeout(_timeout);
      await (cancelToken?.wait(handshake) ?? handshake);
    } on TimeoutException {
      await subscription.cancel();
      await socket.close(WebSocketStatus.goingAway);
      throw const TencentRealtimeAsrException(
        '腾讯云实时识别握手超时',
        kind: TencentRealtimeErrorKind.network,
      );
    } catch (_) {
      await subscription.cancel();
      await socket.close(WebSocketStatus.goingAway);
      rethrow;
    }

    return TencentRealtimeAsrSession._(
      socket: socket,
      subscription: subscription,
      finished: finished,
      getFinalText: () => finalText,
      getFailure: () => failure,
    );
  }

  String _voiceId() =>
      '${_clock().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}';

  static String _canonicalQuery(Map<String, String> values) {
    final keys = values.keys.toList()..sort();
    return keys
        .map((key) => '$key=${Uri.encodeQueryComponent(values[key]!)}')
        .join('&');
  }

  static TencentRealtimeErrorKind _kindForCode(int code) {
    if (code == 4004) {
      return TencentRealtimeErrorKind.quota;
    }
    if (code == 4002 || code == 4003 || code == 401 || code == 403) {
      return TencentRealtimeErrorKind.authentication;
    }
    return TencentRealtimeErrorKind.response;
  }

  static String _messageForCode(int code) {
    return switch (code) {
      4002 || 401 || 403 => '腾讯云实时识别鉴权失败，请检查 APPID 和密钥',
      4003 => '腾讯云实时识别服务未开通，请在腾讯云控制台开通',
      4004 => '腾讯云实时识别资源包已耗尽',
      4005 => '腾讯云账户欠费，实时识别已停用，请检查腾讯云账户',
      4006 => '腾讯云实时识别并发已达上限，请稍后重试',
      4007 => '腾讯云实时识别无法解码音频，请重试',
      4008 || 4009 => '腾讯云实时识别连接中断，请重试',
      6001 => '腾讯云实时识别不支持当前访问区域，请检查账号地区和网络',
      _ => '腾讯云实时识别失败（错误码 $code）',
    };
  }

  void close() {
    if (_ownsAppIdClient) _appIdClient.close();
  }
}

final class TencentRealtimeAsrSession {
  TencentRealtimeAsrSession._({
    required this._socket,
    required this._subscription,
    required this._finished,
    required this._getFinalText,
    required this._getFailure,
  });

  final WebSocket _socket;
  final StreamSubscription<Object?> _subscription;
  final Completer<void> _finished;
  final String Function() _getFinalText;
  final TencentRealtimeAsrException? Function() _getFailure;
  bool _ended = false;
  bool _ending = false;
  Future<void>? _closing;
  final _pendingAudio = <int>[];
  final _audioDrained = Completer<void>();
  Timer? _sendTimer;

  static const int _packetBytes = 6400;

  void add(Uint8List bytes) {
    if (_ended || _ending || bytes.isEmpty || _getFailure() != null) return;
    _pendingAudio.addAll(bytes);
    _sendTimer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _sendPendingAudio(),
    );
  }

  Future<String> end() async {
    try {
      final failure = _getFailure();
      if (failure != null) throw failure;
      if (_ended) return _getFinalText();
      _ending = true;
      if (_pendingAudio.isEmpty) {
        _sendEndMarker();
      } else {
        _sendTimer ??= Timer.periodic(
          const Duration(milliseconds: 200),
          (_) => _sendPendingAudio(),
        );
      }
      await _audioDrained.future.timeout(const Duration(seconds: 15));
      await _finished.future.timeout(const Duration(seconds: 15));
      return _getFinalText().trim();
    } finally {
      await _close();
    }
  }

  Future<void> cancel() async {
    _ended = true;
    _sendTimer?.cancel();
    _pendingAudio.clear();
    if (!_audioDrained.isCompleted) _audioDrained.complete();
    if (!_finished.isCompleted) _finished.complete();
    await _close();
  }

  void _sendPendingAudio() {
    if (_ended) return;
    if (_getFailure() != null) {
      _sendTimer?.cancel();
      _pendingAudio.clear();
      if (!_audioDrained.isCompleted) _audioDrained.complete();
      return;
    }
    final count = _pendingAudio.length >= _packetBytes
        ? _packetBytes
        : _ending
            ? _pendingAudio.length
            : 0;
    if (count > 0) {
      final packet = Uint8List.fromList(_pendingAudio.take(count).toList());
      _pendingAudio.removeRange(0, count);
      _socket.add(packet);
    }
    if (_ending && _pendingAudio.isEmpty) _sendEndMarker();
  }

  void _sendEndMarker() {
    if (_ended) return;
    _ended = true;
    _sendTimer?.cancel();
    _socket.add(jsonEncode(<String, String>{'type': 'end'}));
    if (!_audioDrained.isCompleted) _audioDrained.complete();
  }

  Future<void> _close() => _closing ??= _closeSocket();

  Future<void> _closeSocket() async {
    _sendTimer?.cancel();
    _pendingAudio.clear();
    await _subscription.cancel();
    await _socket.close(WebSocketStatus.normalClosure);
  }
}
