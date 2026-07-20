import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';

String _validPayload({String? apkUrl}) {
  return jsonEncode({
    'packageName': 'com.poemath.app',
    'versionName': '1.2.0',
    'versionCode': 2,
    'tagName': 'v1.2.0',
    'channel': 'stable',
    'apkUrl': apkUrl ?? 'https://updates.example.com/poemath.apk',
    'apkSha256': 'a' * 64,
    'apkSize': 1234,
    'mandatory': false,
    'notes': '修复问题',
  });
}

AppUpdateInfo _updateInfo() {
  return const AppUpdateInfo(
    packageName: 'com.poemath.app',
    versionName: '1.2.0',
    versionCode: 2,
    tagName: 'v1.2.0',
    channel: 'stable',
    apkUrl: 'https://updates.example.com/poemath.apk',
    apkSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    apkSize: 4,
    mandatory: false,
    notes: '修复问题',
  );
}

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'poemath_update_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('fetchLatest 解析并校验更新清单', () async {
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      client: MockClient.streaming((request, bodyStream) async {
        expect(request, isA<http.AbortableRequest>());
        expect(request.headers['Accept'], 'application/json');
        return http.StreamedResponse(
          Stream.value(utf8.encode(_validPayload())),
          200,
        );
      }),
    );

    final update = await client.fetchLatest();
    expect(update.packageName, equals('com.poemath.app'));
    expect(update.versionCode, equals(2));
    expect(update.apkSha256, equals('a' * 64));
  });

  test('清单校验失败时抛出明确错误', () async {
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(_validPayload(apkUrl: 'file:///tmp/update.apk')),
          200,
        ),
      ),
    );

    final update = await client.fetchLatest();
    expect(update.apkUrl, startsWith('file:'));
    await expectLater(
      client.downloadApk(update),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.message,
          'message',
          '安装包下载地址不正确',
        ),
      ),
    );
  });

  test('未配置更新地址和取消令牌可独立验证', () async {
    final client = UpdateClient(updateUrl: '  ');
    expect(client.isConfigured, isFalse);
    await expectLater(
      client.fetchLatest(),
      throwsA(isA<UpdateConfigurationException>()),
    );

    final token = UpdateDownloadCancelToken();
    token.cancel();
    expect(
      () => token.throwIfCancelled(),
      throwsA(isA<UpdateCancelledException>()),
    );
  });

  test('请求超时必须大于零', () {
    expect(
      () => UpdateClient(
        updateUrl: 'https://updates.example.com/latest.json',
        requestTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('fetchLatest 超时转换为明确的更新错误', () async {
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(_validPayload(), 200);
      }),
    );

    await expectLater(
      client.fetchLatest(),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.message,
          'message',
          '检查更新超时',
        ),
      ),
    );
  });

  test('下载使用 AbortableRequest 并写入注入的临时目录', () async {
    final progress = <({int received, int? total})>[];
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      temporaryDirectoryProvider: () async => temporaryDirectory,
      client: MockClient.streaming((request, bodyStream) async {
        expect(request, isA<http.AbortableRequest>());
        return http.StreamedResponse(
          Stream.value([1, 2, 3, 4]),
          200,
          contentLength: 4,
        );
      }),
    );

    final file = await client.downloadApk(
      _updateInfo(),
      onProgress: (received, total) {
        progress.add((received: received, total: total));
      },
    );

    expect(file.path, startsWith(temporaryDirectory.path));
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(progress.last, (received: 4, total: 4));
  });

  test('持续收到数据时不按总下载时长超时', () async {
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      requestTimeout: const Duration(milliseconds: 50),
      temporaryDirectoryProvider: () async => temporaryDirectory,
      client: MockClient.streaming((request, bodyStream) async {
        final abortableRequest = request as http.AbortableRequest;
        return http.StreamedResponse(
          _periodicStreamUntilAbort(
            abortTrigger: abortableRequest.abortTrigger!,
            requestUri: request.url,
          ),
          200,
          contentLength: 4,
        );
      }),
    );

    final file = await client.downloadApk(_updateInfo());

    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });

  test('预先取消时不发出请求且不创建临时目录', () async {
    var requestCount = 0;
    var directoryRequested = false;
    final token = UpdateDownloadCancelToken()..cancel();
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      temporaryDirectoryProvider: () async {
        directoryRequested = true;
        return temporaryDirectory;
      },
      client: MockClient.streaming((request, bodyStream) async {
        requestCount++;
        return http.StreamedResponse(Stream.value([1]), 200);
      }),
    );

    await expectLater(
      client.downloadApk(_updateInfo(), cancelToken: token),
      throwsA(isA<UpdateCancelledException>()),
    );
    expect(requestCount, 0);
    expect(directoryRequested, isFalse);
  });

  test('下载中取消会删除半成品 APK', () async {
    final responseController = StreamController<List<int>>();
    final firstChunkWritten = Completer<void>();
    final token = UpdateDownloadCancelToken();
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      temporaryDirectoryProvider: () async => temporaryDirectory,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          responseController.stream,
          200,
          contentLength: 4,
        );
      }),
    );

    final download = client.downloadApk(
      _updateInfo(),
      cancelToken: token,
      onProgress: (received, total) {
        if (received > 0 && !firstChunkWritten.isCompleted) {
          firstChunkWritten.complete();
        }
      },
    );
    responseController.add([1, 2]);
    await firstChunkWritten.future;
    token.cancel();
    responseController.add([3, 4]);
    await responseController.close();

    await expectLater(download, throwsA(isA<UpdateCancelledException>()));
    expect(await _downloadFile(temporaryDirectory).exists(), isFalse);
  });

  test('下载流超时会返回明确错误并删除半成品 APK', () async {
    final responseController = StreamController<List<int>>();
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      requestTimeout: const Duration(milliseconds: 10),
      temporaryDirectoryProvider: () async => temporaryDirectory,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(responseController.stream, 200);
      }),
    );

    await expectLater(
      client.downloadApk(_updateInfo()),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.message,
          'message',
          '安装包下载超时',
        ),
      ),
    );
    await responseController.close();
    expect(await _downloadFile(temporaryDirectory).exists(), isFalse);
  });
}

File _downloadFile(Directory temporaryDirectory) {
  return File(
    '${temporaryDirectory.path}/poemath_update/poemath-1.2.0+2.apk',
  );
}

Stream<List<int>> _periodicStreamUntilAbort({
  required Future<void> abortTrigger,
  required Uri requestUri,
}) {
  late final StreamController<List<int>> controller;
  Timer? timer;
  var value = 0;
  controller = StreamController<List<int>>(
    onListen: () {
      timer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
        value++;
        controller.add([value]);
        if (value == 4) {
          timer.cancel();
          unawaited(controller.close());
        }
      });
      unawaited(
        abortTrigger.then((_) {
          if (controller.isClosed) return;
          timer?.cancel();
          controller.addError(http.RequestAbortedException(requestUri));
          unawaited(controller.close());
        }),
      );
    },
    onCancel: () => timer?.cancel(),
  );
  return controller.stream;
}
