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

/// 某一天的云请求用量快照（三类齐全，缺失的为 0）。
class DailyCloudUsage {
  const DailyCloudUsage({required this.date, required this.counts});

  /// 该日零点（只用到年月日）。
  final DateTime date;
  final Map<CloudUsageKind, int> counts;

  int of(CloudUsageKind kind) => counts[kind] ?? 0;

  /// 三类合计。
  int get total => CloudUsageKind.values.fold(0, (sum, k) => sum + of(k));
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
  String get dayKey => _dateKey(_clock());

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

  /// 某一天的某类用量。date 为 null 或解析异常按 0。
  int usedOn(DateTime date, CloudUsageKind kind) {
    if (!_ready) return 0;
    final value = HiveBoxes.meta.get(
      'cloud_usage:${_dateKey(date)}:${kind.key}',
    );
    return value is int && value >= 0 ? value : 0;
  }

  /// 最近 [days] 天的用量，**按日期升序**，含今天。
  ///
  /// 缺失的日期补 0 而非跳过：柱状图的 x 轴是等距时间轴，跳过会让柱子
  /// 错位到相邻日期上，读出来的趋势是错的。注意存储层只保留 32 天
  /// （见 [reserve] 的清理），days 超过该窗口时更早的日期恒为 0。
  List<DailyCloudUsage> recentDaily(int days) {
    assert(days > 0, 'days 必须为正');
    final today = _clock();
    return List.generate(days, (i) {
      // 从最早的一天开始生成，保证升序且末项为今天。
      final date = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: days - 1 - i));
      return DailyCloudUsage(
        date: date,
        counts: {
          for (final kind in CloudUsageKind.values)
            kind: usedOn(date, kind),
        },
      );
    });
  }

  /// 日期键，与 [dayKey] 同格式（`YYYY-MM-DD`，月日补零）。
  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';

  Future<void> setLimit(CloudUsageKind kind, int? value) async {
    ParentAccessService.instance.assertAllowed();
    if (value != null && (value < 0 || value > 100000)) {
      throw const FormatException('每日请求额度须为 0–100000，留空表示不限');
    }
    await HiveBoxes.settings.put('cloud_daily_limit_${kind.key}', value ?? -1);
  }

  static const String _usagePrefix = 'cloud_usage:';

  /// 读取本机全部用量计数，供本机诊断及测试使用；不随备份导出。
  static Map<String, int> exportCounts() {
    if (!Hive.isBoxOpen('meta')) return const {};
    final result = <String, int>{};
    for (final key in HiveBoxes.meta.keys) {
      final name = key.toString();
      if (!name.startsWith(_usagePrefix)) continue;
      final value = HiveBoxes.meta.get(key);
      if (value is int && value >= 0) result[name] = value;
    }
    return result;
  }

  /// 内部替换本机计数（显式本机重置/测试用途）。
  /// 备份恢复不得调用：当日已消耗额度是设备事实，不能由备份覆盖。
  static Future<void> replaceCounts(Map<String, int> counts) async {
    final valid = <String, int>{};
    for (final entry in counts.entries) {
      if (!entry.key.startsWith(_usagePrefix)) continue;
      if (entry.value < 0) continue;
      valid[entry.key] = entry.value;
    }
    final existing = HiveBoxes.meta.keys
        .whereType<String>()
        .where((key) => key.startsWith(_usagePrefix))
        .toList();
    await HiveBoxes.meta.deleteAll(existing);
    await HiveBoxes.meta.putAll(valid);
  }

  Future<void> reserve(CloudUsageKind kind) {
    if (!_ready) return Future<void>.value();
    final previous = _tail;
    final work = () async {
      try {
        await previous;
      } on Object {/* 失败不阻塞下一次请求。 */}
      final maximum = limit(kind);
      final key = '$_usagePrefix$dayKey:${kind.key}';
      final saved = HiveBoxes.meta.get(key);
      final current = saved is int && saved >= 0 ? saved : 0;
      if (maximum != null && current >= maximum) {
        throw CloudQuotaExceededException(kind);
      }
      await HiveBoxes.meta.put(key, current + 1);
      // 仅保留最近 32 个日期的计数，不触碰结算或练习草稿。
      final cutoff = _clock().subtract(const Duration(days: 32));
      final keys = HiveBoxes.meta.keys.whereType<String>().where((key) {
        if (!key.startsWith(_usagePrefix)) return false;
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
