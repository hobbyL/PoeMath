// test/core/services/speech/legacy_speech_cleanup_test.dart
//
// 遗留清理测试：模型目录删除幂等、设置键清除、失败不抛出。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/speech/legacy_speech_cleanup.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

import '../../../helpers/hive_test_helper.dart';

void main() {
  late Directory tempSupportDir;

  setUp(() async {
    await setUpHiveForTesting();
    tempSupportDir = await Directory.systemTemp.createTemp('speech_cleanup_');
  });

  tearDown(() async {
    if (tempSupportDir.existsSync()) {
      tempSupportDir.deleteSync(recursive: true);
    }
    await tearDownHiveForTesting();
  });

  test('删除已存在的遗留模型目录', () async {
    final modelDir = Directory('${tempSupportDir.path}/speech_models/inner');
    modelDir.createSync(recursive: true);
    File('${modelDir.path}/encoder.onnx').writeAsBytesSync(List.filled(8, 1));

    await LegacySpeechCleanup.run(
      supportDirectoryProvider: () async => tempSupportDir,
    );

    expect(
      Directory('${tempSupportDir.path}/speech_models').existsSync(),
      false,
    );
  });

  test('模型目录不存在时静默跳过', () async {
    await LegacySpeechCleanup.run(
      supportDirectoryProvider: () async => tempSupportDir,
    );

    expect(
      Directory('${tempSupportDir.path}/speech_models').existsSync(),
      false,
    );
  });

  test('删除 settings box 中的遗留高精度开关键', () async {
    await HiveBoxes.settings.put('tencent_asr_high_accuracy_enabled', true);

    await LegacySpeechCleanup.run(
      supportDirectoryProvider: () async => tempSupportDir,
    );

    expect(
      HiveBoxes.settings.get('tencent_asr_high_accuracy_enabled'),
      isNull,
    );
  });

  test('键不存在时重复执行幂等', () async {
    await LegacySpeechCleanup.run(
      supportDirectoryProvider: () async => tempSupportDir,
    );
    await LegacySpeechCleanup.run(
      supportDirectoryProvider: () async => tempSupportDir,
    );

    expect(
      HiveBoxes.settings.get('tencent_asr_high_accuracy_enabled'),
      isNull,
    );
  });

  test('目录提供方抛错时不传播异常', () async {
    await expectLater(
      LegacySpeechCleanup.run(
        supportDirectoryProvider: () async => throw const FileSystemException(
          'boom',
        ),
      ),
      completes,
    );
  });
}
