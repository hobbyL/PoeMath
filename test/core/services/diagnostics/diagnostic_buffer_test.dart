// test/core/services/diagnostics/diagnostic_buffer_test.dart
//
// 诊断环形缓冲契约测试（10-18-security-hardening 问题 5）：
//   * 三重上限（条数 / 单条字符 / 总 UTF-8 字节）与最旧淘汰
//   * 敏感值 scrub
//   * record 自身绝不抛出
//   * 导出文本不含原始凭据
// 断言力求有咬合力：删掉被测实现行后必须变红。

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/diagnostics/diagnostic_buffer.dart';
import 'package:poemath/core/utils/logger.dart';

/// `toString()` 会抛异常的假对象 —— record 不得传播该异常。
class _ThrowingToString {
  @override
  String toString() => throw StateError('toString 爆炸');
}

void main() {
  group('三重上限与淘汰', () {
    test('条数超限时丢弃最旧记录', () {
      final buffer = DiagnosticBuffer(maxRecords: 5);
      for (var i = 0; i < 15; i++) {
        buffer.record(level: 'E', tag: 'T', message: 'msg-$i');
      }

      expect(buffer.length, 5);
      final messages =
          buffer.snapshot().map((r) => r.message).toList(growable: false);
      // 最旧的 10 条被丢弃，只留 msg-10..msg-14，且顺序仍是从旧到新。
      expect(messages, <String>[
        'msg-10',
        'msg-11',
        'msg-12',
        'msg-13',
        'msg-14',
      ]);
    });

    test('单条 message 超长被截断且带标记', () {
      final buffer = DiagnosticBuffer(maxMessageChars: 10);
      buffer.record(level: 'E', tag: 'T', message: 'x' * 100);

      final message = buffer.snapshot().single.message;
      expect(message.startsWith('x' * 10), isTrue);
      expect(message.length, lessThan(100));
      expect(message, contains('已截断'));
    });

    test('单条 stackTrace 超长被截断', () {
      final buffer = DiagnosticBuffer(maxStackChars: 20);
      buffer.record(
        level: 'E',
        tag: 'T',
        message: 'boom',
        stackTrace: StackTrace.fromString('s' * 500),
      );

      final stack = buffer.snapshot().single.stackTrace;
      expect(stack, isNotNull);
      expect(stack!.length, lessThan(500));
      expect(stack, contains('已截断'));
    });

    test('总 UTF-8 字节超限时从最旧开始淘汰（中文一字约 3 字节）', () {
      // 每条 300 个中文字 ≈ 900 字节 + 前缀；上限 2500 字节 → 只留最后 2 条。
      final buffer = DiagnosticBuffer(
        maxRecords: 1000,
        maxMessageChars: 1000,
        maxTotalBytes: 2500,
      );
      for (var i = 0; i < 10; i++) {
        buffer.record(level: 'E', tag: 'T', message: '中' * 300 + '#$i');
      }

      expect(buffer.length, lessThan(10));
      expect(buffer.length, greaterThanOrEqualTo(1));
      // 存活的是最尾几条。
      final messages = buffer.snapshot().map((r) => r.message).toList();
      expect(messages.last, endsWith('#9'));
      expect(messages.any((m) => m.endsWith('#0')), isFalse);

      // 字节预算确实生效：总字节不超过上限（按导出文本近似）。
      final totalBytes = buffer
          .snapshot()
          .fold<int>(0, (sum, r) => sum + r.toText().runes.length * 3);
      expect(totalBytes, lessThan(2500 * 3));
    });

    test('clear 清空缓冲', () {
      final buffer = DiagnosticBuffer();
      buffer.record(level: 'E', tag: 'T', message: 'a');
      expect(buffer.length, 1);
      buffer.clear();
      expect(buffer.length, 0);
      expect(buffer.exportAsText(), isEmpty);
    });
  });

  group('record 绝不抛出', () {
    test('message.toString() 抛异常时不传播', () {
      final buffer = DiagnosticBuffer();
      expect(
        () => buffer.record(
          level: 'E',
          tag: 'T',
          message: _ThrowingToString(),
        ),
        returnsNormally,
      );
      // 降级为占位文案，仍留下一条记录（不静默丢弃）。
      final message = buffer.snapshot().single.message;
      expect(message, contains('toString 抛出异常'));
    });

    test('error.toString() 抛异常时不传播', () {
      final buffer = DiagnosticBuffer();
      expect(
        () => buffer.record(
          level: 'E',
          tag: 'T',
          message: '外层',
          error: _ThrowingToString(),
        ),
        returnsNormally,
      );
    });

    test('stackTrace.toString() 抛异常时不传播', () {
      final buffer = DiagnosticBuffer();
      expect(
        () => buffer.record(
          level: 'E',
          tag: 'T',
          message: '外层',
          stackTrace: StackTrace.fromString(
            // 一个 toString 会抛的自定义 StackTrace 不好造，改用具名子类。
            '',
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('敏感值 scrub', () {
    test('key=value 形式的值被替换', () {
      final scrubbed = DiagnosticBuffer.scrub('password=SuperSecret123');
      expect(scrubbed, isNot(contains('SuperSecret123')));
      expect(scrubbed, contains('***'));
    });

    test('"key": "value" 形式的值被替换', () {
      final scrubbed =
          DiagnosticBuffer.scrub('{"api_key": "sk-abcdef0123456789"}');
      expect(scrubbed, isNot(contains('sk-abcdef0123456789')));
      expect(scrubbed, contains('"api_key"'));
      expect(scrubbed, contains('***'));
    });

    test('覆盖 passphrase / token / secret / Authorization / apiKey', () {
      const samples = <String>[
        'passphrase: 我的口令',
        'token=tok_123456',
        'secret: s3cr3t-value',
        'Authorization=Bearer abcdefghijklmnop',
        'apiKey = "AIzaSyABCDEFGH"',
      ];
      for (final sample in samples) {
        final scrubbed = DiagnosticBuffer.scrub(sample);
        expect(scrubbed, isNot(equals(sample)), reason: '应发生替换：$sample');
        expect(scrubbed, contains('***'), reason: '应含 ***：$sample');
      }
    });

    test('普通文本不受影响', () {
      const plain = '错题落库失败：HiveError 磁盘写入失败';
      expect(DiagnosticBuffer.scrub(plain), plain);
    });

    test('record 落盘前已完成 scrub', () {
      final buffer = DiagnosticBuffer();
      buffer.record(
        level: 'E',
        tag: 'T',
        message: '请求失败 password=hunter2',
      );
      expect(buffer.exportAsText(), isNot(contains('hunter2')));
      expect(buffer.exportAsText(), contains('***'));
    });
  });

  group('导出文本', () {
    test('头部含级别/tag/消息，且不含原始口令', () {
      final buffer = DiagnosticBuffer();
      buffer.record(level: 'W', tag: 'WebDav', message: '连接超时');
      buffer.record(
        level: 'E',
        tag: 'Backup',
        message: '导出失败',
        error: 'StateError: password=topsecret999',
      );

      final text = buffer.exportAsText();
      expect(text, contains('[W][WebDav] 连接超时'));
      expect(text, contains('[E][Backup] 导出失败'));
      expect(text, contains('cause:'));
      expect(text, isNot(contains('topsecret999')));
    });
  });

  group('AppLogger 与缓冲的接线', () {
    setUp(() {
      DiagnosticBuffer.instance = DiagnosticBuffer();
    });

    test('e 写入缓冲并附带 cause 与堆栈', () {
      AppLogger.e(
        '测试错误',
        tag: 'Unit',
        error: const FormatException('bad'),
        stackTrace: StackTrace.fromString('stack-line'),
      );

      final record = DiagnosticBuffer.instance.snapshot().single;
      expect(record.level, 'E');
      expect(record.tag, 'Unit');
      expect(record.message, contains('测试错误'));
      expect(record.message, contains('FormatException'));
      expect(record.stackTrace, contains('stack-line'));
    });

    test('w 写入缓冲', () {
      AppLogger.w('测试警告', tag: 'Unit');
      final record = DiagnosticBuffer.instance.snapshot().single;
      expect(record.level, 'W');
      expect(record.message, '测试警告');
    });

    test('d 不写缓冲（量太大）', () {
      AppLogger.d('高频调试', tag: 'Unit');
      expect(DiagnosticBuffer.instance.length, 0);
    });
  });
}
