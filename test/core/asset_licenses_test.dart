import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('应用许可入口收录音效署名与 PDFium 原生依赖声明', () async {
    registerAssetLicenses();
    final licenses = await LicenseRegistry.licenses
        .where(
          (entry) => entry.packages.any(
            (name) =>
                name.contains('提示音') ||
                name.contains('童趣答题语音') ||
                name.contains('PDFium'),
          ),
        )
        .toList();
    final child = licenses.singleWhere(
      (entry) => entry.packages.contains('童趣答题语音 — 雨多多'),
    );
    final text = child.paragraphs.map((paragraph) => paragraph.text).join('\n');
    expect(text, contains('作者：雨多多'));
    expect(text, contains('《答对咯》《答错啦》'));
    expect(text, contains('CC-BY'));
    expect(text, contains('https://www.ear0.com/sound/show/soundid-34357'));
    expect(text, contains('https://www.ear0.com/sound/show/soundid-34358'));
    expect(text, contains('直接使用用户下载的原始 MP3'));
    final completion = licenses.singleWhere(
      (entry) => entry.packages.contains('完成提示音 — Kenney'),
    );
    expect(
      completion.paragraphs.map((p) => p.text).join('\n'),
      contains('CC0'),
    );
    final pdfium = licenses.singleWhere(
      (entry) => entry.packages.contains('PDFium 原生阅读引擎'),
    );
    final pdfiumText = pdfium.paragraphs.map((p) => p.text).join('\n');
    expect(pdfiumText, contains('Copyright 2014-2025 Benoit Blanchon'));
    expect(pdfiumText, contains('licenses/pdfium.txt'));
    expect(pdfiumText, contains('licenses/freetype.txt'));
    expect(pdfiumText, contains('licenses/libjpeg_turbo.md'));
  });
}
