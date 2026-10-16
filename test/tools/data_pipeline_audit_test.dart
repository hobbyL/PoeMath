import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 独立导入工具包不属于应用运行时依赖。
// ignore: avoid_relative_lib_imports
import '../../tools/poem_importer/lib/poem_importer.dart';

void main() {
  test('少年词境和连续破折号保持逐字拼音对齐', () {
    expect(generatePinyin('少年——石径斜'), 'shào nián — — shí jìng xiá');
  });

  test('公式参数的YAML隐式字段必须在导入时失败', () async {
    final dir = await Directory.systemTemp.createTemp('poemath-formula-test-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/formula.yaml');
    await source.writeAsString('''
formulas:
  - id: bad
    category: algebra
    name: bad
    formula_text: a
    formula_latex: a
    grade: 1
    params:
      - {symbol: a,b,c, meaning: 参数}
''');
    expect(
        () => FormulasImporter(
                sourcePath: source.path, outputPath: '${dir.path}/out.json',)
            .run(),
        throwsFormatException,);
    expect(File('${dir.path}/out.json').existsSync(), isFalse);
  });

  test('全部内置资源通过注释、作者和逐字拼音结构校验', () {
    final report = SchemaValidator().validateAll('assets/data');
    expect(report.errors, isEmpty, reason: report.render());
    expect(report.warnings, isEmpty, reason: report.render());
  });
}
