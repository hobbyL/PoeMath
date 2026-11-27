import 'math_problem.dart';

/// 一组口算的运算次数。null（由调用方表示）为沿用自动出题。
/// 拷贝并冻结输入，避免开始练习后设置变化修改本轮请求。
class OperationCounts {
  const OperationCounts._(this.values);

  factory OperationCounts(Iterable<int> values) =>
      OperationCounts.fromJson(values.toList());

  factory OperationCounts.fromJson(Object? value) {
    if (value is! List ||
        value.isEmpty ||
        value.length > 3 ||
        value.any((v) => v is! int || v < 1 || v > 3) ||
        value.toSet().length != value.length) {
      throw const FormatException('运算次数须为 1、2、3 中的不重复选项');
    }
    return OperationCounts._(
      List<int>.unmodifiable(List<int>.from(value)..sort()),
    );
  }

  factory OperationCounts.decode(String raw) {
    if (!RegExp(r'^[123](,[123])*$').hasMatch(raw)) {
      throw const FormatException('运算次数格式无效');
    }
    return OperationCounts(raw.split(',').map(int.parse));
  }

  final List<int> values;
  bool contains(int count) => values.contains(count);
  String encode() => values.join(',');
  List<int> toJson() => values;
  String get label => '${values.join('、')} 次运算';

  static Set<int> supportedForMode(ProblemMode? mode) => switch (mode) {
    ProblemMode.chain || ProblemMode.withBrackets => const {2, 3},
    ProblemMode.vertical => const {1},
    _ => const {1, 2, 3},
  };

  /// 切换题型保留交集；无交集时选择最小可用次数，调用方须显示调整。
  OperationCounts forMode(ProblemMode? mode) {
    final supported = supportedForMode(mode);
    final kept = values.where(supported.contains).toList();
    return OperationCounts(kept.isEmpty ? [supported.first] : kept);
  }

  @override
  bool operator ==(Object other) =>
      other is OperationCounts && encode() == other.encode();

  @override
  int get hashCode => Object.hashAll(values);
}
