"""Security SDK floors must reject a downgrade, including matching old CI pins."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import check_project_contracts as contracts


class ProjectContractsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for relative in (".fvmrc", "pubspec.yaml", "assets/legal/privacy_policy.md"):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(contracts.ROOT / relative, target)
        shutil.copytree(contracts.ROOT / ".github/workflows", self.root / ".github/workflows")
        self.root_patch = patch.object(contracts, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def test_current_security_pins_pass(self):
        contracts.check()

    def test_old_sdk_rejected_even_when_ci_matches(self):
        (self.root / ".fvmrc").write_text(json.dumps({"flutter": "3.44.6"}))
        for workflow in (self.root / ".github/workflows").glob("*.yml"):
            workflow.write_text(workflow.read_text().replace("3.47.8", "3.44.6"))
        with self.assertRaisesRegex(ValueError, "FVM"):
            contracts.check()

    def test_old_ci_rejected(self):
        workflow = self.root / ".github/workflows/ci-test.yml"
        workflow.write_text(workflow.read_text().replace("3.47.8", "3.44.6"))
        with self.assertRaisesRegex(ValueError, "CI"):
            contracts.check()

    def test_lower_dart_floor_rejected(self):
        pubspec = self.root / "pubspec.yaml"
        pubspec.write_text(pubspec.read_text().replace(">=3.13.7 <4.0.0", ">=3.6.0 <4.0.0"))
        with self.assertRaisesRegex(ValueError, "Dart"):
            contracts.check()

    def test_lower_flutter_floor_rejected(self):
        pubspec = self.root / "pubspec.yaml"
        pubspec.write_text(pubspec.read_text().replace('flutter: ">=3.47.8"', 'flutter: ">=3.27.0"'))
        with self.assertRaisesRegex(ValueError, "Flutter"):
            contracts.check()


if __name__ == "__main__":
    unittest.main()
