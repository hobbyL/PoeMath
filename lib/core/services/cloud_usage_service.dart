import 'package:hive/hive.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/core/services/parent_access_service.dart';

enum CloudUsageKind {
  llm('AI', 'llm', 30),
  asr('语音识别', 'asr', 60),
  tts('云朗读', 'tts', 120);

  const CloudUsageKind(this.label, this.key, this.defaultLimit);
  final String label;
  final String key;
  final int defaultLimit;
}

class CloudQuotaExceededException implements Exception {
  const CloudQuotaExceededException(this.kind);
  final CloudUsageKind kind;
  String get message => '今日${kind.label}请求额度已用完，可请家长调整额度';
  @override
  String toString() => message;
}

/// 设备本地的请求次数限制；不是供应商账单，也不随备份恢复归零。
/// 所有真实发送点在 HTTP 调用之前预留；已发送失败、探测和重试也计数。
class CloudUsageService {
  CloudUsageService({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  static final instance = CloudUsageService();
  static Future<void> _tail = Future<void>.value();
  final DateTime Function() _clock;

  // 纯客户端单元测试可以不启动应用；生产应用在 Hive 就绪前不会创建服务。
  bool get _ready => Hive.isBoxOpen('meta') && Hive.isBoxOpen('settings');
  String get dayKey {
    final date = _clock();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  int? limit(CloudUsageKind kind) {
    if (!_ready) return kind.defaultLimit;
    final value = HiveBoxes.settings.get('cloud_daily_limit_${kind.key}');
    if (value == -1) return null;
    return value is int && value >= 0 && value <= 100000
        ? value
        : kind.defaultLimit;
  }

  int used(CloudUsageKind kind) {
    if (!_ready) return 0;
    final value = HiveBoxes.meta.get('cloud_usage:$dayKey:${kind.key}');
    return value is int && value >= 0 ? value : 0;
  }

  Future<void> setLimit(CloudUsageKind kind, int? value) async {
    ParentAccessService.instance.assertAllowed();
    if (value != null && (value < 0 || value > 100000)) {
      throw const FormatException('每日请求额度须为 0–100000，留空表示不限');
    }
    await HiveBoxes.settings.put('cloud_daily_limit_${kind.key}', value ?? -1);
  }

  Future<void> reserve(CloudUsageKind kind) {
    if (!_ready) return Future<void>.value();
    final previous = _tail;
    final work = () async {
      try {
        await previous;
      } on Object {/* 失败不阻塞下一次请求。 */}
      final maximum = limit(kind);
      final key = 'cloud_usage:$dayKey:${kind.key}';
      final saved = HiveBoxes.meta.get(key);
      final current = saved is int && saved >= 0 ? saved : 0;
      if (maximum != null && current >= maximum) {
        throw CloudQuotaExceededException(kind);
      }
      await HiveBoxes.meta.put(key, current + 1);
      // 仅保留最近 32 个日期的计数，不触碰结算或练习草稿。
      final cutoff = _clock().subtract(const Duration(days: 32));
      final keys = HiveBoxes.meta.keys.whereType<String>().where((key) {
        if (!key.startsWith('cloud_usage:')) return false;
        final date = DateTime.tryParse(key.split(':')[1]);
        return date != null &&
            date.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day));
      }).toList();
      if (keys.isNotEmpty) {
        try {
          await HiveBoxes.meta.deleteAll(keys);
        } on Object {/* 计数已落盘，旧日期清理稍后重试。 */}
      }
    }();
    _tail = work;
    return work;
  }
}
