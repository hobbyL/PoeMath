// lib/core/services/diagnostics/diagnostic_buffer.dart
//
// 层级：core/services/diagnostics
// 职责：生产环境（release）诊断日志的内存环形缓冲。
//
// 背景：release 包中 `AppLogger` 原先完全静默（全部方法裹在 `kDebugMode` 内），
// 崩溃与可恢复异常没有任何落脚点。本缓冲给 `w` / `e` 级别一个有限的记录处，
// 并支撑「关于 → 导出诊断日志」入口。
//
// 设计要点（见 10-18-security-hardening design.md §5.2）：
//   * **纯内存，不落盘**。落盘会引出「缓冲文件是否加密」的问题，把诊断与
//     Hive 加密耦合成循环依赖；内存实现天然「重启即清空」，避免诊断数据
//     无限累积成隐私负债。
//   * **代价**：应用被杀后缓冲丢失 —— 用户没能在崩溃后导出就什么也没有。
//     这是有意接受的权衡。
//   * **三重上限**（条数 / 单条字符 / 总 UTF-8 字节），任一超限都从最旧开始淘汰。
//   * `record()` **绝不抛出**：自身异常吞掉并降级为无操作，绝不影响主流程。
//   * scrub 是**兜底**，不是许可证：`logging-guidelines.md` 的 Never Log
//     清单照旧生效（凭据、密码、Token、完整诗词正文一律不得传入）。
//
// 不登记进 `BackupService._settingsValueType` —— 缓冲根本不在 Hive 里，
// 因此天然排除于本地备份 / WebDAV 上传。有防回归测试锁定。

import 'dart:convert';

/// 一条诊断记录。字段均已截断，可直接序列化。
class DiagnosticRecord {
  const DiagnosticRecord({
    required this.at,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });

  /// 记录时刻（秒精度即可）。
  final DateTime at;

  /// 级别，`'W'` 或 `'E'`。
  final String level;

  /// 日志 tag。
  final String tag;

  /// 已截断的消息正文。
  final String message;

  /// 已截断的堆栈；无堆栈为 null。
  final String? stackTrace;

  /// 导出用的单条文本（多行）。
  String toText() {
    final buffer = StringBuffer()
      ..write('[${_isoSeconds(at)}][$level][$tag] $message');
    final stack = stackTrace;
    if (stack != null && stack.isNotEmpty) {
      buffer.write('\n$stack');
    }
    return buffer.toString();
  }

  static String _isoSeconds(DateTime value) {
    final local = value.toLocal();
    final iso = local.toIso8601String();
    // 去掉毫秒/微秒尾巴，保留到秒。
    final dot = iso.indexOf('.');
    return dot == -1 ? iso : iso.substring(0, dot);
  }
}

/// 内存环形缓冲。生产实例是 [instance]（单例）。
class DiagnosticBuffer {
  DiagnosticBuffer({
    this.maxRecords = 200,
    this.maxMessageChars = 500,
    this.maxStackChars = 2000,
    this.maxTotalBytes = 256 * 1024,
    DateTime Function()? now,
  })  : assert(maxRecords > 0),
        assert(maxMessageChars > 0),
        assert(maxStackChars > 0),
        assert(maxTotalBytes > 0),
        _now = now ?? DateTime.now;

  /// 生产单例。测试可替换（`DiagnosticBuffer.instance = DiagnosticBuffer()`）。
  static DiagnosticBuffer instance = DiagnosticBuffer();

  /// 条数上限。
  final int maxRecords;

  /// 单条 message 字符上限。
  final int maxMessageChars;

  /// 单条 stackTrace 字符上限。
  final int maxStackChars;

  /// 缓冲总字节上限（按 UTF-8 编码后的长度计，中文一字约 3 字节）。
  final int maxTotalBytes;

  final DateTime Function() _now;
  final List<DiagnosticRecord> _records = <DiagnosticRecord>[];

  int _totalBytes = 0;

  /// 当前记录条数（供关于页显示）。
  int get length => _records.length;

  /// 只读快照，最旧在前。
  List<DiagnosticRecord> snapshot() =>
      List<DiagnosticRecord>.unmodifiable(_records);

  /// 记录一条。**绝不允许抛出** —— 任何内部异常都被吞掉并降级为无操作。
  void record({
    required String level,
    required String tag,
    required Object? message,
    StackTrace? stackTrace,
    Object? error,
  }) {
    try {
      final rawMessage = error == null
          ? _safeToString(message)
          : '${_safeToString(message)}\n  cause: ${_safeToString(error)}';
      final scrubbed = scrub(rawMessage);
      final body = _truncate(scrubbed, maxMessageChars);
      final stack = stackTrace == null
          ? null
          : _truncate(scrub(stackTrace.toString()), maxStackChars);

      final entry = DiagnosticRecord(
        at: _now(),
        level: level,
        tag: _truncate(scrub(tag), maxMessageChars),
        message: body,
        stackTrace: (stack == null || stack.isEmpty) ? null : stack,
      );
      _append(entry);
    } on Object {
      // 诊断缓冲自身绝不传播异常 —— 记录日志不能影响主流程。
    }
  }

  /// 清空（供导出后或测试使用）。
  void clear() {
    _records.clear();
    _totalBytes = 0;
  }

  /// 导出为纯文本。头部 — 由调用方补应用名/版本/时间（见 `about_page.dart`）。
  String exportAsText() {
    final buffer = StringBuffer();
    for (final record in _records) {
      buffer.writeln(record.toText());
    }
    return buffer.toString();
  }

  /// 敏感值清洗：`key=value` / `"key": "value"` / `key: value` 里的值替换为 `***`。
  ///
  /// 这是**兜底**防线；调用方仍须遵守 `logging-guidelines.md` 的 Never Log 清单。
  static String scrub(String input) {
    var output = input.replaceAllMapped(
      RegExp(r'''(["']?Authorization["']?\s*[:=]\s*)[^\r\n,;}\]]*''',
          caseSensitive: false,),
      (match) => '${match.group(1)}***',
    );
    for (final key in _sensitiveKeys) {
      output = output.replaceAllMapped(
        _patternFor(key),
        (match) => '${match.group(1)}***',
      );
    }
    return output;
  }

  static const List<String> _sensitiveKeys = <String>[
    'password',
    'passphrase',
    'api_key',
    'apiKey',
    'token',
    'secret',
    'secretId',
    'secretKey',
    'secret_id',
    'secret_key',
    'access_token',
    'refresh_token',
  ];

  /// 构造单个 key 的匹配式，覆盖三种常见书写：
  /// `password=abc`、`"password": "abc"`、`password: abc`。
  ///
  /// group(1) = key（可含引号包裹）与其后的分隔符；
  /// 引号内的空格也是凭据的一部分，不能只清洗第一个单词。
  static RegExp _patternFor(String key) {
    final escaped = RegExp.escape(key);
    // 裸值允许空格；以行尾、逗号、分号或结构结束符为边界。
    return RegExp(
      '(["\']?$escaped["\']?\\s*[:=]\\s*)'
      r'''(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\r\n,;})\]]+)''',
      caseSensitive: false,
    );
  }

  static String _safeToString(Object? value) {
    if (value == null) return 'null';
    try {
      return value.toString();
    } on Object {
      return '<toString 抛出异常>';
    }
  }

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}…[已截断]';
  }

  void _append(DiagnosticRecord entry) {
    final bytes = utf8.encode(entry.toText()).length;
    _records.add(entry);
    _totalBytes += bytes;

    // 条数超限
    while (_records.length > maxRecords) {
      _evictOldest();
    }
    // 总字节超限（至少保留 1 条，避免单条超大记录把缓冲清空）
    while (_totalBytes > maxTotalBytes && _records.length > 1) {
      _evictOldest();
    }
  }

  void _evictOldest() {
    if (_records.isEmpty) return;
    final removed = _records.removeAt(0);
    _totalBytes -= utf8.encode(removed.toText()).length;
  }
}
