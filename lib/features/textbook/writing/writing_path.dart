import 'dart:typed_data';
import 'dart:ui';

/// 极简 SVG path 解析（仅 M/L/Q/C/Z 与绝对坐标）。
///
/// Make Me a Hanzi 的 strokes 实测只含这四种命令（2333 字统计：M 21324、
/// Q 210934、L 23089、C 13615、Z 21324），因此不做 arc / 相对坐标支持。
///
/// 坐标为 Make Me a Hanzi 的 1024×1024 画布，y 已在资产生成期翻转为屏幕方向。
Path parseSvgPath(String data) {
  final tokens = _tokenize(data);
  final path = Path();
  var i = 0;
  String? command;
  double? nextNumber() {
    if (i >= tokens.length) return null;
    final token = tokens[i];
    if (token is double) {
      i++;
      return token;
    }
    return null;
  }

  while (i < tokens.length) {
    final token = tokens[i];
    if (token is String) {
      command = token;
      i++;
      if (command == 'Z') {
        path.close();
        command = null;
        continue;
      }
    }
    if (command == null) {
      // 非法输入：跳过孤立数字，保证不抛异常（降级渲染）。
      i++;
      continue;
    }
    final arity = switch (command) {
      'M' || 'L' => 2,
      'Q' => 4,
      'C' => 6,
      _ => 0,
    };
    if (arity == 0) {
      i++;
      continue;
    }
    final args = <double>[];
    while (args.length < arity) {
      final value = nextNumber();
      if (value == null) break;
      args.add(value);
    }
    if (args.length < arity) {
      // 参数不全：丢弃剩余，避免死循环。
      break;
    }
    switch (command) {
      case 'M':
        path.moveTo(args[0], args[1]);
        // SVG 规范：M 后续的连续坐标对按 L 处理。
        command = 'L';
      case 'L':
        path.lineTo(args[0], args[1]);
      case 'Q':
        path.quadraticBezierTo(args[0], args[1], args[2], args[3]);
      case 'C':
        path.cubicTo(args[0], args[1], args[2], args[3], args[4], args[5]);
    }
  }
  return path;
}

/// 分词：命令字母为 String，参数为 double。
List<Object> _tokenize(String data) {
  final tokens = <Object>[];
  var index = 0;
  while (index < data.length) {
    final char = data[index];
    if (char == 'M' || char == 'L' || char == 'Q' || char == 'C' || char == 'Z') {
      tokens.add(char);
      index++;
      continue;
    }
    if (_isNumberStart(char)) {
      final start = index;
      index++;
      while (index < data.length && _isNumberChar(data[index])) {
        index++;
      }
      final value = double.tryParse(data.substring(start, index));
      if (value != null) tokens.add(value);
      continue;
    }
    index++;
  }
  return tokens;
}

bool _isNumberStart(String char) =>
    char == '-' || char == '+' || _isDigit(char) || char == '.';

bool _isNumberChar(String char) =>
    _isDigit(char) || char == '.' || char == '-' || char == '+';

bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// 由 strokes path 构建整字轮廓（描红底图 / 参考字形渲染）。
Path characterOutline(List<String> strokes) {
  final path = Path();
  for (final stroke in strokes) {
    path.addPath(parseSvgPath(stroke), Offset.zero);
  }
  return path;
}

/// 田字格内的画布变换：把 1024×1024 暂存坐标等比缩放并居中到 [canvasSize] 方框。
///
/// Make Me a Hanzi 字形在 1024 画布中约占 900×900（四周留白），直接等比缩放
/// 即可保持原书字重与留白比例。返回 4×4 列主序矩阵，可直接给
/// `Canvas.transform` / `Canvas.drawPath` 的变换使用。
Float64List hanziCanvasMatrix(double canvasSize) {
  final scale = canvasSize / 1024;
  final dx = canvasSize / 2 - 512 * scale;
  final dy = canvasSize / 2 - 512 * scale;
  return Float64List.fromList([
    scale, 0, 0, 0, // 第 1 列
    0, scale, 0, 0, // 第 2 列
    0, 0, 1, 0, // 第 3 列
    dx, dy, 0, 1, // 第 4 列（平移）
  ]);
}