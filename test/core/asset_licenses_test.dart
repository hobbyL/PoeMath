import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('应用许可入口收录打包音效的作者、原始来源和修改说明', () async {
    registerAssetLicenses();
    final licenses = await LicenseRegistry.licenses
        .where(
          (entry) => entry.packages.any(
            (name) => name.contains('提示音') || name.contains('童趣答题语音'),
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
  });
}
