import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';

/// Deterministic server-side frames; the production client still signs and
/// streams audio using its normal WebSocket protocol.
class TestTencentRealtimeSocket extends Fake implements WebSocket {
  TestTencentRealtimeSocket({this.text = '实时新结果'});

  final String text;
  final incoming = StreamController<Object?>.broadcast();
  final endSent = Completer<void>();
  final List<Object?> sentFrames = [];
  Completer<void>? closeGate;
  int? errorCode;
  String? errorMessage;
  int? finalErrorCode;
  bool holdResult = false;
  bool closed = false;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = incoming.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    incoming.add(
      jsonEncode({
        'code': errorCode ?? 0,
        'message': errorMessage ?? 'success',
        'voice_id': 'synthetic-voice',
      }),
    );
    return subscription;
  }

  void receiveText(String value, {bool stable = false}) {
    incoming.add(
      jsonEncode({
        'code': 0,
        'result': {
          'index': 0,
          'voice_text_str': value,
          'slice_type': stable ? 2 : 1,
        },
      }),
    );
  }

  void receiveError(int code, {String? message}) {
    incoming.add(jsonEncode({'code': code, 'message': message ?? 'failure'}));
  }

  @override
  void add(dynamic data) {
    sentFrames.add(data is List<int> ? List<int>.from(data) : data);
    if (data is String && data.contains('"end"')) {
      if (!endSent.isCompleted) endSent.complete();
      if (!holdResult) {
        incoming.add(
          jsonEncode({
            'code': finalErrorCode ?? 0,
            'result': {'index': 0, 'voice_text_str': text, 'slice_type': 2},
            'final': 1,
          }),
        );
      }
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await closeGate?.future;
    closed = true;
    await incoming.close();
  }
}
