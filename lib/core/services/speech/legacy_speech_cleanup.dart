// lib/core/services/speech/legacy_speech_cleanup.dart
//
// 遗留数据清理：移除本地 Sherpa-ONNX 识别后，清理由旧版本产生的：
//   1. <ApplicationSupport>/speech_models/   （asset 拷贝出的模型目录，~24MB）
//   2. settings box 的 tencent_asr_high_accuracy_enabled 遗留键
// （旧备份恢复也可能带回该键，此处统一兜底删除。）

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

/// Settings box 遗留键（原 SettingsRepository 高精度开关，已无读取方）。
const String _legacyHighAccuracyKey = 'tencent_asr_high_accuracy_enabled';

final class LegacySpeechCleanup {
  const LegacySpeechCleanup._();

  /// 删除遗留模型目录与设置键。幂等；失败仅记录日志，绝不抛出。
  static Future<void> run({
    Future<Directory> Function()? supportDirectoryProvider,
  }) async {
    try {
      final supportDirectory =
          await (supportDirectoryProvider ?? getApplicationSupportDirectory)();
      final modelDirectory = Directory('${supportDirectory.path}/speech_models');
      if (await modelDirectory.exists()) {
        await modelDirectory.delete(recursive: true);
        AppLogger.d('已清理遗留本地语音模型目录', tag: 'SpeechCleanup');
      }
    } on Object catch (error) {
      AppLogger.w('清理遗留本地语音模型目录失败（忽略）：$error', tag: 'SpeechCleanup');
    }

    try {
      await HiveBoxes.settings.delete(_legacyHighAccuracyKey);
    } on Object catch (error) {
      AppLogger.w('清理遗留语音识别设置键失败（忽略）：$error', tag: 'SpeechCleanup');
    }
  }
}
