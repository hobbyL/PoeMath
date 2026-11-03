"""Guard against lock-file and native-binary downgrades independently."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_pdfium_security as security


class PdfiumSecurityTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / ".dart_tool").mkdir()
        versions = {"pdfrx": "2.11.0", "pdfrx_engine": "0.9.0",
                    "pdfium_dart": "0.4.1", "pdfium_flutter": "0.4.1"}
        self.lock = self.root / "pubspec.lock"
        self.lock.write_text("packages:\n" + "".join(
            f'  {name}:\n    version: "{version}"\n'
            for name, version in versions.items()
        ))
        for name, version in versions.items():
            package = self.root / "packages" / name
            package.mkdir(parents=True)
            (package / "pubspec.yaml").write_text(f"version: {version}\n")
        self.hook = self.root / "packages/pdfium_dart/hook/build.dart"
        self.hook.parent.mkdir()
        self.hook.write_text("const _pdfiumRelease = 'chromium%2F8125';\n")
        self.podspec = self.root / "packages/pdfium_flutter/darwin/pdfium_flutter.podspec"
        self.podspec.parent.mkdir()
        self.podspec.write_text('PDFIUM_URL = "https://example.invalid/PDFium-chromium-8125-date.xcframework.zip"\n')
        # Relative rootUri is how pub's package_config points outside .dart_tool.
        (self.root / ".dart_tool/package_config.json").write_text(json.dumps({
            "packages": [{"name": name, "rootUri": f"../packages/{name}/"}
                         for name in versions]
        }))
        replacement = patch.object(security, "ROOT", self.root)
        replacement.start()
        self.addCleanup(replacement.stop)

    def test_safe_resolved_dependencies_pass(self):
        security.check()

    def test_old_indirect_dependency_rejected(self):
        self.lock.write_text(self.lock.read_text().replace(
            'pdfium_dart:\n    version: "0.4.1"',
            'pdfium_dart:\n    version: "0.2.5"'
        ))
        with self.assertRaisesRegex(ValueError, "已知漏洞"):
            security.check()

    def test_native_hook_downgrade_rejected_even_when_package_versions_match(self):
        self.hook.write_text("const _pdfiumRelease = 'chromium%2F7811';\n")
        with self.assertRaisesRegex(ValueError, "原生构建 hook"):
            security.check()

    def test_apple_binary_downgrade_rejected(self):
        self.podspec.write_text('PDFIUM_URL = "PDFium-chromium-7811-date.xcframework.zip"\n')
        with self.assertRaisesRegex(ValueError, "Apple 原生库"):
            security.check()

    def test_resolved_package_must_match_lock_file(self):
        (self.root / "packages/pdfium_dart/pubspec.yaml").write_text("version: 0.2.5\n")
        with self.assertRaisesRegex(ValueError, "锁文件不一致"):
            security.check()

    def test_missing_lock_dependency_rejected(self):
        self.lock.write_text(self.lock.read_text().replace('  pdfrx_engine:\n', '  renamed:\n'))
        with self.assertRaisesRegex(ValueError, "缺少 PDF 依赖"):
            security.check()


if __name__ == "__main__":
    unittest.main()
