import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// 单字逐笔书写数据（Make Me a Hanzi / Arphic 公共授权字体派生）。
///
/// 坐标系：Make Me a Hanzi 的 1024×1024 画布（字形实际占约 -64~1083 的裕量），
/// y 轴已在资产生成期翻转为屏幕方向（y 向下为正），运行时零转换。
/// medians 为每笔骨架折线，直接用于笔顺动画与几何比对（见 writing_geometry）。
class CharacterStrokeData {
  const CharacterStrokeData({
    required this.character,
    required this.strokes,
    required this.medians,
  });

  final String character;

  /// SVG path 字符串（M/L/Q/C/Z 命令），描红底图与参考字形渲染用。
  final List<String> strokes;

  /// 每笔骨架折线（原始画布坐标）。
  final List<List<Point<double>>> medians;

  int get strokeCount => strokes.length;
}

/// 资产加载失败（缺文件/坏数据）：调用方捕获后按 AC6 降级，不崩溃。
class WritingStrokeDataException implements Exception {
  const WritingStrokeDataException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => cause == null
      ? 'WritingStrokeDataException: $message'
      : 'WritingStrokeDataException: $message ($cause)';
}

/// 资产字节读取器；测试可注入假实现，生产默认走 rootBundle。
typedef WritingStrokeAssetLoader = Future<Uint8List> Function(String assetPath);

const writingStrokeAssetPath = 'assets/data/writing_strokes.json.gz';

Map<String, CharacterStrokeData>? _cache;
Future<Map<String, CharacterStrokeData>>? _loading;

Future<Uint8List> _rootBundleLoader(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 加载完整笔顺资产并静态缓存；可安全重复调用（并发调用共享同一次加载）。
///
/// 失败抛 [WritingStrokeDataException] 由调用方降级处理（AC6）；
/// 失败结果不进缓存，下一次调用会重试。
Future<Map<String, CharacterStrokeData>> loadWritingStrokeData({
  WritingStrokeAssetLoader? loader,
}) {
  final cache = _cache;
  if (cache != null) return Future.value(cache);
  return _loading ??= _load(loader ?? _rootBundleLoader);
}

Future<Map<String, CharacterStrokeData>> _load(
  WritingStrokeAssetLoader loader,
) async {
  try {
    final bytes = await loader(writingStrokeAssetPath);
    final parsed = _decodeAsset(bytes);
    _cache = parsed;
    return parsed;
  } on WritingStrokeDataException {
    rethrow;
  } on Object catch (error) {
    throw WritingStrokeDataException('书写笔顺数据加载失败', error);
  } finally {
    _loading = null;
  }
}

/// 解码 gzip + JSON 资产；顶层结构错误抛 [WritingStrokeDataException]，
/// 单字条目不合契约则跳过该字（缺字走 AC6 降级，不拖垮整份资产）。
Map<String, CharacterStrokeData> _decodeAsset(Uint8List bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(GZipCodec().decode(bytes)));
  } on Object catch (error) {
    throw WritingStrokeDataException('书写笔顺数据解码失败', error);
  }
  if (decoded is! Map<String, dynamic>) {
    throw const WritingStrokeDataException('书写笔顺数据顶层须为对象');
  }
  final characters = decoded['characters'];
  if (characters is! Map<String, dynamic>) {
    throw const WritingStrokeDataException('书写笔顺数据缺少 characters 字段');
  }
  final result = <String, CharacterStrokeData>{};
  for (final entry in characters.entries) {
    final data = _parseCharacter(entry.key, entry.value);
    if (data != null) result[entry.key] = data;
  }
  return result;
}

CharacterStrokeData? _parseCharacter(String character, Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final rawStrokes = raw['strokes'];
  final rawMedians = raw['medians'];
  if (rawStrokes is! List || rawMedians is! List) return null;
  if (rawStrokes.length != rawMedians.length) return null;
  final strokes = <String>[];
  final medians = <List<Point<double>>>[];
  for (var i = 0; i < rawStrokes.length; i++) {
    final path = rawStrokes[i];
    final median = rawMedians[i];
    if (path is! String || median is! List) return null;
    final points = <Point<double>>[];
    for (final point in median) {
      if (point is! List || point.length < 2) return null;
      final x = point[0];
      final y = point[1];
      if (x is! num || y is! num) return null;
      points.add(Point<double>(x.toDouble(), y.toDouble()));
    }
    if (points.isEmpty) return null;
    strokes.add(path);
    medians.add(List.unmodifiable(points));
  }
  return CharacterStrokeData(
    character: character,
    strokes: List.unmodifiable(strokes),
    medians: List.unmodifiable(medians),
  );
}

/// 查询单字笔顺数据；无该字返回 null（调用方降级，AC6）。
///
/// 首次调用触发加载；加载失败抛 [WritingStrokeDataException] 由调用方捕获。
Future<CharacterStrokeData?> strokeDataFor(String character) async {
  final data = await loadWritingStrokeData();
  return data[character];
}

/// 基于已加载缓存的同步查询；未加载或无数据返回 false。
bool hasStrokeDataSync(String character) =>
    _cache != null && _cache!.containsKey(character);

/// 仅测试用：清空缓存，恢复未加载状态。
void resetWritingStrokeDataForTest() {
  _cache = null;
  _loading = null;
}
