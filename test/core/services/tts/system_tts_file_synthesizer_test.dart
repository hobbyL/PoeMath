import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/tts/system_tts_file_synthesizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/textbook-file-tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('narration-channel-');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('文件合成保留音色语速与唯一请求身份，校验后清理私有临时文件', () async {
    final calls = <MethodCall>[];
    final files = <File>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'describeVoice') return 'engine|v1|zh-CN';
      if (call.method != 'synthesize') return null;
      final bytes = Uint8List(44)
        ..setRange(0, 4, 'RIFF'.codeUnits)
        ..setRange(8, 12, 'WAVE'.codeUnits);
      final file = await File('${directory.path}/${files.length}.wav')
          .writeAsBytes(bytes);
      files.add(file);
      return file.path;
    });
    final adapter = AndroidSystemTtsFileSynthesizer(channel: channel);
    const voice = {'name': 'local', 'locale': 'zh-CN'};
    expect(await adapter.describeVoice(voice, 0.7), 'engine|v1|zh-CN');
    for (var i = 0; i < 2; i++) {
      final bytes = await adapter.synthesize(
          sessionId: 21, text: '完整正文。', voice: voice, speed: 0.7,);
      expect(bytes.length, 44);
      expect(await files.last.exists(), false);
    }
    final requests = calls
        .where((c) => c.method == 'synthesize')
        .map((c) => c.arguments as Map)
        .toList();
    expect(requests.map((a) => a['requestId']), [1, 2]);
    expect(requests.first, containsPair('sessionId', 21));
    expect(requests.first, containsPair('voice', voice));
    expect(requests.first, containsPair('speed', 0.7));
    await adapter.cancelSession(21);
    await adapter.dispose();
    expect(calls.map((c) => c.method).toList().sublist(3),
        ['cancelSession', 'dispose'],);
  });
  test('无效音频和平台失败均为中文领域异常，损坏文件同样删除', () async {
    final file =
        await File('${directory.path}/bad.wav').writeAsString('not a wave');
    messenger.setMockMethodCallHandler(channel, (_) async => file.path);
    final adapter = AndroidSystemTtsFileSynthesizer(channel: channel);
    await expectLater(
        adapter.synthesize(sessionId: 22, text: '正文。', voice: null, speed: 0.5),
        throwsA(isA<NarrationException>()),);
    expect(await file.exists(), false);
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'INIT_FAILED'),);
    await expectLater(
        adapter.describeVoice(null, 0.5), throwsA(isA<NarrationException>()),);
    await adapter.cancelSession(22);
    await adapter.dispose();
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'INVALID_TEXT'));
    await expectLater(adapter.synthesize(sessionId: 23, text: '过长正文', voice: null, speed: 0.5),
      throwsA(isA<NarrationException>().having((e) => e.message, 'message', contains('内容审核'))),);
  });
}
