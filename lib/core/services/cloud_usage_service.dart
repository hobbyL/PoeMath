import 'dart:async';

import 'package:hive/hive.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/core/utils/calendar_dates.dart';
import 'package:poemath/core/services/parent_access_service.dart';

enum CloudUsageKind {
  llm('AI', 'llm', 30),
  asr('语音识别', 'asr', 60),
  tts('云朗读', 'tts', 120),
  imageGeneration('图片生成', 'image', null);

  const CloudUsageKind(this.label, this.key, this.defaultLimit);
  final String label;
  final String key;
  final int? defaultLimit;

  /// AI 改为统计成功结果，旧请求计数不能推断成功次数，保留原值但不沿用。
  String get counterKey => this == llm ? 'llm_success_v1' : key;
}

class CloudQuotaExceededException implements Exception {
  const CloudQuotaExceededException(this.kind, {this.inProgress = false});
  final CloudUsageKind kind;
  final bool inProgress;
  String get message => inProgress
      ? 'AI 正在处理中，请稍后重试'
      : kind == CloudUsageKind.llm
      ? '今日AI成功次数已达上限，可请家长调整额度'
      : '今日${kind.label}请求额度已用完，可请家长调整额度';
  @override
  String toString() => message;
}

/// 某一天的云服务用量快照（所有种类齐全，缺失的为 0）。
class DailyCloudUsage {
  const DailyCloudUsage({required this.date, required this.counts});

  /// 该日零点（只用到年月日）。
  final DateTime date;
  final Map<CloudUsageKind, int> counts;

  int of(CloudUsageKind kind) => counts[kind] ?? 0;

  /// 所有种类合计。
  int get total => CloudUsageKind.values.fold(0, (sum, k) => sum + of(k));
}

/// 设备本地的用量限制；AI 按成功结果计次，其余服务按发送请求计次。
/// 图片生成只统计用量，不设置应用内每日上限。
/// 不是供应商账单，也不随备份恢复归零。
class CloudUsageService {
  CloudUsageService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  static final instance = CloudUsageService();
  static Future<void> _tail = Future<void>.value();
  static final _llmScope = Object();
  static final _pendingLlm = Expando<Set<_LlmUsageReservation>>();
  final DateTime Function() _clock;

  // 纯客户端单元测试可以不启动应用；生产应用在 Hive 就绪前不会创建服务。
  bool get _ready => Hive.isBoxOpen('meta') && Hive.isBoxOpen('settings');
  String get dayKey => _dateKey(_clock());

  int? limit(CloudUsageKind kind) {
    if (kind == CloudUsageKind.imageGeneration) return null;
    if (!_ready) return kind.defaultLimit;
    final value = HiveBoxes.settings.get('cloud_daily_limit_${kind.key}');
    if (value == -1) return null;
    return value is int && value >= 0 && value <= 100000
        ? value
        : kind.defaultLimit;
  }

  int used(CloudUsageKind kind) {
    if (!_ready) return 0;
    final value = HiveBoxes.meta.get('cloud_usage:$dayKey:${kind.counterKey}');
    return value is int && value >= 0 ? value : 0;
  }

  /// 某一天的某类用量。date 为 null 或解析异常按 0。
  int usedOn(DateTime date, CloudUsageKind kind) {
    if (!_ready) return 0;
    final value = HiveBoxes.meta.get(
      'cloud_usage:${_dateKey(date)}:${kind.counterKey}',
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
      final date = DateTime(today.year, today.month, today.day - days + 1 + i);
      return DailyCloudUsage(
        date: date,
        counts: {
          for (final kind in CloudUsageKind.values) kind: usedOn(date, kind),
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
    if (kind == CloudUsageKind.imageGeneration && value != null) {
      throw const FormatException('图片生成不设置应用内每日上限');
    }
    if (value != null && (value < 0 || value > 100000)) {
      throw const FormatException('每日额度须为 0–100000，留空表示不限');
    }
    await HiveBoxes.settings.put('cloud_daily_limit_${kind.key}', value ?? -1);
  }

  static const String _usagePrefix = 'cloud_usage:';

  /// 同一逻辑操作中的工具探测、重试和嵌套 AI 调用共用一个临时名额。
  /// 只有成功结果才落盘；异常、取消与无有效结果均释放名额。
  /// 成功次数归属操作开始日，跨午夜不会占用新一天的名额。
  Future<T> trackLlmSuccess<T>(
    Future<T> Function() action, {
    void Function()? check,
    bool Function(T result)? isSuccessful,
  }) async {
    check?.call();
    if (_hasLlmScope) return action();
    final reservation = await _beginLlmUsage(check);
    try {
      return await runZoned(() async {
        final result = await action();
        check?.call();
        if (isSuccessful?.call(result) ?? true) {
          await reservation.complete(check);
        }
        return result;
      }, zoneValues: {_llmScope: reservation});
    } finally {
      reservation.release();
    }
  }

  /// 流必须正常结束才计次；提前停止或出错时保留已展示内容但不扣次数。
  Stream<T> trackLlmStream<T>(
    Stream<T> Function() action, {
    void Function()? check,
  }) async* {
    check?.call();
    if (_hasLlmScope) {
      await for (final chunk in action()) {
        yield chunk;
      }
      return;
    }
    final reservation = await _beginLlmUsage(check);
    try {
      await for (final chunk in action()) {
        yield chunk;
      }
      check?.call();
      await reservation.complete(check);
    } finally {
      reservation.release();
    }
  }

  bool get _hasLlmScope =>
      (Zone.current[_llmScope] as _LlmUsageReservation?)?._active ?? false;

  Future<_LlmUsageReservation> _beginLlmUsage(void Function()? check) {
    // 无存储时没有共享计数；不要让静态写队列保留已结束调用的 Zone。
    if (!_ready) {
      return Future.value(_LlmUsageReservation(this, null, dayKey));
    }
    return _serialize(() async {
      check?.call();
      final box = _ready ? HiveBoxes.meta : null;
      final day = dayKey;
      if (box != null) {
        final pending = _pendingLlm[box] ??= <_LlmUsageReservation>{};
        final maximum = limit(CloudUsageKind.llm);
        final completed = used(CloudUsageKind.llm);
        final count =
            completed +
            pending.where((reservation) => reservation.day == day).length;
        if (maximum != null && count >= maximum) {
          throw CloudQuotaExceededException(
            CloudUsageKind.llm,
            inProgress: completed < maximum,
          );
        }
      }
      final reservation = _LlmUsageReservation(this, box, day);
      if (box != null) _pendingLlm[box]!.add(reservation);
      return reservation;
    });
  }

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // 尾链始终恢复成功，单次失败不阻塞后续请求。
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

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

  Future<void> reserve(CloudUsageKind kind, {void Function()? check}) {
    if (kind == CloudUsageKind.llm) {
      return trackLlmSuccess(() async {}, check: check);
    }
    check?.call();
    if (!_ready) return Future<void>.value();
    final previous = _tail;
    final work = () async {
      try {
        await previous;
      } on Object {
        /* 失败不阻塞下一次请求。 */
      }
      check?.call();
      final maximum = limit(kind);
      final key = '$_usagePrefix$dayKey:${kind.counterKey}';
      final saved = HiveBoxes.meta.get(key);
      final current = saved is int && saved >= 0 ? saved : 0;
      if (maximum != null && current >= maximum) {
        throw CloudQuotaExceededException(kind);
      }
      await HiveBoxes.meta.put(key, current + 1);
      await _pruneCounts(HiveBoxes.meta);
    }();
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  Future<void> _pruneCounts(Box<dynamic> box) async {
    // 仅保留最近 32 个日期的计数，不触碰结算或练习草稿。
    final cutoff = addCalendarDays(_clock(), -32);
    final keys = box.keys.whereType<String>().where((key) {
      if (!key.startsWith(_usagePrefix)) return false;
      final date = DateTime.tryParse(key.split(':')[1]);
      return date != null &&
          date.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day));
    }).toList();
    if (keys.isNotEmpty) {
      try {
        await box.deleteAll(keys);
      } on Object {
        /* 计数已落盘，旧日期清理稍后重试。 */
      }
    }
  }
}

class _LlmUsageReservation {
  _LlmUsageReservation(this.usage, this.box, this.day);
  final CloudUsageService usage;
  final Box<dynamic>? box;
  final String day;
  bool _active = true;

  Future<void> complete(void Function()? check) {
    if (box == null) {
      check?.call();
      return Future<void>.value();
    }
    return CloudUsageService._serialize(() async {
      check?.call();
      final target = box;
      if (!_active || target == null) return;
      final key = 'cloud_usage:$day:${CloudUsageKind.llm.counterKey}';
      final value = target.get(key);
      final current = value is int && value >= 0 ? value : 0;
      await target.put(key, current + 1);
      release();
      await usage._pruneCounts(target);
    });
  }

  void release() {
    if (!_active) return;
    _active = false;
    final target = box;
    if (target != null) CloudUsageService._pendingLlm[target]?.remove(this);
  }
}
