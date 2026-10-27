import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/domain/writing_stroke_data.dart';

/// 笔顺资产加载（一次加载静态缓存，失败抛 [WritingStrokeDataException]）。
///
/// 供写一写字卡、练习页与进度仓库共享，避免重复解压 2.4MB gzip 资产。
final writingStrokeDataProvider =
    FutureProvider<WritingStrokeAsset>((ref) async {
  final characters = await loadWritingStrokeData();
  return WritingStrokeAsset(characters);
});

/// 资产查询包装：保留同步查询能力，避免 UI 层直接碰全局缓存。
class WritingStrokeAsset {
  const WritingStrokeAsset(this._characters);
  final Map<String, CharacterStrokeData> _characters;

  bool hasStrokeDataSync(String character) =>
      _characters.containsKey(character);

  CharacterStrokeData? operator [](String character) => _characters[character];

  int get count => _characters.length;
}