// 资产裁剪脚本：Make Me a Hanzi graphics.txt → assets/data/writing_strokes.json
//
// 用法：
//   ~/.pub-cache/bin/fvm dart run tool/extract_strokes.dart \
//     --graphics /tmp/mmah_graphics.txt \
//     --characters /tmp/mmah_book_write_list.txt \
//     --output assets/data/writing_strokes.json.gz
//
// 预处理（构建期一次性完成，运行时零转换）：
//   1. y 轴翻转：y' = 900 - y（Makemeahanzi 坐标系 y 向上，翻转后符合
//      Flutter 屏幕坐标 y 向下；见 Make Me a Hanzi graphics.txt 坐标说明）
//   2. medians 弧长重采样到 ≤ resampleMax 点（默认 16），消除采样率差异
//   3. strokes 保留原始 SVG path 字符串（M/L/Q/Z 四命令，描红渲染用），
//      path 内 y 坐标同样翻转
//
// 许可：数据源自 Arphic Public License 字体（经 Make Me a Hanzi 加工），
// 输出资产头部含修改声明；原版许可全文见 assets/legal/ARPHICPL.TXT。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const resampleMax = 16;

void main(List<String> args) {
  final options = _parseArgs(args);
  final graphicsFile = File(options['graphics']!);
  final charactersFile = File(options['characters']!);
  final outputFile = File(options['output']!);

  if (!graphicsFile.existsSync()) {
    stderr.writeln('找不到 graphics.txt：${graphicsFile.path}');
    exit(1);
  }
  if (!charactersFile.existsSync()) {
    stderr.writeln('找不到会写字清单：${charactersFile.path}');
    exit(1);
  }

  // 1. 读会写字清单（忽略 # 注释行与空行，一行可含多字）。
  final wanted = <String>{};
  for (final rawLine in charactersFile.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      if (char.trim().isNotEmpty) wanted.add(char);
    }
  }
  stdout.writeln('会写字清单：${wanted.length} 字');

  // 2. 逐行扫 graphics.txt（JSON Lines），命中即转换。
  final characters = <String, Map<String, Object>>{};
  final missing = <String>[];
  final invalid = <String>[];
  for (final rawLine in graphicsFile.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final Map<String, dynamic> entry;
    try {
      entry = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      continue; // 源数据偶有杂行，跳过即可。
    }
    final char = entry['character'] as String?;
    if (char == null || !wanted.contains(char)) continue;
    final strokes = (entry['strokes'] as List?)?.cast<String>();
    final mediansRaw = (entry['medians'] as List?)
        ?.cast<List<dynamic>>()
        .map((points) => points.cast<List<dynamic>>())
        .toList();
    if (strokes == null || mediansRaw == null) {
      invalid.add(char);
      continue;
    }
    if (strokes.length != mediansRaw.length) {
      invalid.add(char);
      continue;
    }
    characters[char] = {
      'strokes': [
        for (final path in strokes) _flipPathY(path),
      ],
      'medians': [
        for (final median in mediansRaw)
          _resampleMedian([
            for (final point in median)
              [
                (point[0] as num).round(),
                900 - (point[1] as num).round(),
              ],
          ]),
      ],
    };
  }
  missing.addAll(wanted.difference(characters.keys.toSet()));

  // 3. 组装输出（license 头 = APL 2(a) 修改声明），gzip 压缩落盘
  //    （完整数据 ~6MB，gzip 后 ~2.4MB；运行时 rootBundle + gzip 一次性解压缓存）。
  final output = <String, dynamic>{
    'license': 'Arphic Public License — original text in '
        'assets/legal/ARPHICPL.TXT. Stroke/median data derived from Arphic '
        'PL KaitiM GB glyphs via Make Me a Hanzi '
        '(github.com/skishore/makemeahanzi). Modifications: y-axis flipped '
        '(y=900-y) and medians resampled to <=16 points per stroke.',
    'characters': characters,
  };
  outputFile.parent.createSync(recursive: true);
  final payload = utf8.encode(jsonEncode(output));
  outputFile.writeAsBytesSync(
    GZipCodec(level: 9).encode(payload),
  );

  // 4. 报告。
  final sizeKb = outputFile.lengthSync();
  stdout
    ..writeln('输出：${outputFile.path}')
    ..writeln('命中 ${characters.length} / ${wanted.length} 字')
    ..writeln('体积：${(sizeKb / 1024).toStringAsFixed(1)} KB（gzip）');
  if (invalid.isNotEmpty) {
    stdout.writeln('数据无效（strokes/medians 不齐）：${invalid.join(' ')}');
  }
  if (missing.isNotEmpty) {
    stdout
      ..writeln('缺数据 ${missing.length} 字（运行时降级，见 AC6）：')
      ..writeln(missing.join(' '));
  }
}

/// 弧长均匀重采样折线到 ≤ [resampleMax] 点。
Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final key = args[i];
    if (!key.startsWith('--')) continue;
    if (i + 1 >= args.length) {
      stderr.writeln('缺少参数值：$key');
      exit(2);
    }
    options[key.substring(2)] = args[++i];
  }
  for (final required in ['graphics', 'characters', 'output']) {
    if (!options.containsKey(required)) {
      stderr.writeln('缺少必需参数 --$required');
      exit(2);
    }
  }
  return options;
}

/// 弧长均匀重采样折线到 ≤ [resampleMax] 点。
/// 输入为 [x, y] 数组；点数不足时原样返回。
List<List<int>> _resampleMedian(List<List<int>> points) {
  if (points.length <= resampleMax) return points;
  final lengths = <double>[0.0];
  for (var i = 1; i < points.length; i++) {
    final dx = (points[i][0] - points[i - 1][0]).toDouble();
    final dy = (points[i][1] - points[i - 1][1]).toDouble();
    lengths.add(lengths.last + math.sqrt(dx * dx + dy * dy));
  }
  final total = lengths.last;
  if (total <= 0) return [points.first];
  final result = <List<int>>[];
  var seg = 1;
  for (var k = 0; k < resampleMax; k++) {
    final target = total * k / (resampleMax - 1);
    while (seg < points.length - 1 && lengths[seg] < target) {
      seg++;
    }
    final before = lengths[seg - 1];
    final span = lengths[seg] - before;
    final t = span <= 0 ? 0.0 : (target - before) / span;
    result.add([
      (points[seg - 1][0] + t * (points[seg][0] - points[seg - 1][0])).round(),
      (points[seg - 1][1] + t * (points[seg][1] - points[seg - 1][1])).round(),
    ]);
  }
  return result;
}

/// 翻转 SVG path 字符串中的 y 坐标（M/L/Q 命令的对应参数位）。
/// 数据实测只含 M/L/Q/Z 四命令（见任务研究 1），不做通用解析。
String _flipPathY(String path) {
  final out = StringBuffer();
  var index = 0;
  var command = ' ';
  var argIndex = 0;
  while (index < path.length) {
    final ch = path[index];
    if (ch == 'M' || ch == 'L' || ch == 'Q' || ch == 'C' || ch == 'Z') {
      command = ch;
      argIndex = 0;
      out.write(ch);
      index++;
      continue;
    }
    if (RegExp(r'[0-9.\-]').hasMatch(ch)) {
      final start = index;
      while (index < path.length && RegExp(r'[0-9.\-]').hasMatch(path[index])) {
        index++;
      }
      final value = double.parse(path.substring(start, index));
      // M/L 的参数位为 x,y；Q 为 cx,cy,x,y；C 为 c1x,c1y,c2x,c2y,x,y
      // —— y 一律出现在每对参数的第 2 位（argIndex 为奇数）。
      final isY = (command == 'M' ||
              command == 'L' ||
              command == 'Q' ||
              command == 'C') &&
          argIndex.isOdd;
      final flipped = isY ? 900 - value : value;
      out.write(
        flipped == flipped.roundToDouble()
            ? flipped.round().toString()
            : flipped.toString(),
      );
      argIndex++;
      continue;
    }
    out.write(ch);
    index++;
  }
  return out.toString();
}
