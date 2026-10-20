import tempfile
import unittest
from pathlib import Path

from release_version import parse_tag, validate_release
from write_signing_properties import escape, write_properties


class ReleaseContractsTest(unittest.TestCase):
    def test_version_bounds_and_collisions(self):
        self.assertEqual(parse_tag("v1.2.3"), ("1.2.3", 10203))
        for tag in ["v0.0.100", "v0.100.0", "v01.2.3", "v1.2", "v1.2.3-rc1", "v0.0.0"]:
            with self.assertRaises(ValueError):
                parse_tag(tag)
        with self.assertRaises(ValueError):
            validate_release("v0.0.2", ["v0.0.3"])
        with self.assertRaises(ValueError):
            validate_release("v0.1.0", ["v0.0.100"])
        with self.assertRaises(ValueError):
            validate_release("v1.0.1", ["v0.100.2"])
        self.assertEqual(validate_release("v0.1.0", ["v0.0.99"])[1], 100)

    def test_signing_special_characters_are_data(self):
        self.assertEqual(escape(" x\\y\nz='$(echo unsafe)'中文"),
                         "\\ x\\\\y\\nz\\='$(echo\\ unsafe)'\\u4e2d\\u6587")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "key.properties"
            write_properties(path, {"KEYSTORE_PASSWORD": "a\nb", "KEY_ALIAS": "x:y",
                                    "KEY_PASSWORD": "p\\q"})
            self.assertIn("storePassword=a\\nb\n", path.read_text())
            self.assertIn("keyAlias=x\\:y\n", path.read_text())


if __name__ == "__main__":
    unittest.main()
