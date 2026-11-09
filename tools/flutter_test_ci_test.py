"""CI must cover every test and expose failures or interrupted reports."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

if __package__:
    from . import run_flutter_test_shard as runner
    from .run_flutter_test_shard import ROOT, select_files
    from .summarize_flutter_tests import read_report, render
else:
    import run_flutter_test_shard as runner
    from run_flutter_test_shard import ROOT, select_files
    from summarize_flutter_tests import read_report, render


class ShardTest(unittest.TestCase):
    def test_all_repository_files_appear_exactly_once(self):
        shards = [select_files(ROOT, index, 4) for index in range(4)]
        actual = [path for shard in shards for path in shard]
        expected = {path.relative_to(ROOT).as_posix()
                    for path in (ROOT / "test").rglob("*_test.dart")}
        self.assertEqual(set(actual), expected)
        self.assertEqual(len(actual), len(expected))
        self.assertLessEqual(max(map(len, shards)) - min(map(len, shards)), 1)

    def test_invalid_or_empty_shards_fail(self):
        for index, count in [(-1, 4), (4, 4), (0, 0)]:
            with self.assertRaises(ValueError):
                select_files(ROOT, index, count)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "no test files"):
                select_files(Path(directory), 0, 4)

    def test_launch_failure_preserves_exit_code_and_clears_old_report(self):
        with tempfile.TemporaryDirectory() as directory:
            report_dir = Path(directory)
            report = report_dir / "flutter-tests.json"
            report.write_text('{"type":"done","success":true}', encoding="utf-8")
            arguments = ["runner", "--total-shards", "4", "--shard-index", "2",
                         "--report-dir", directory]
            with patch.object(sys, "argv", arguments), \
                    patch.object(runner.subprocess, "run", return_value=
                                 subprocess.CompletedProcess([], 7)) as launch, \
                    patch("builtins.print"):
                self.assertEqual(runner.main(), 7)
            selected = select_files(ROOT, 2, 4)
            self.assertEqual(launch.call_args.args[0][-len(selected):], selected)
            self.assertIn("--concurrency=2", launch.call_args.args[0])
            self.assertEqual((report_dir / "test-files.txt").read_text().splitlines(),
                             selected)
            self.assertEqual(report.read_text(), "")
            self.assertFalse(read_report(report).ok)


class ReportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "report.json"
        self.events = [{"type": "suite", "time": 0, "suite": {
            "id": 0, "path": "/runner/test/home_test.dart"}}]

    def start(self, test_id, name):
        self.events.append({"type": "testStart", "time": test_id * 100,
                            "test": {"id": test_id, "suiteID": 0, "name": name}})

    def finish(self, test_id, result="success", hidden=False, skipped=False):
        self.events.append({"type": "testDone", "time": test_id * 100 + 50,
                            "testID": test_id, "result": result,
                            "hidden": hidden, "skipped": skipped})

    def read(self, suffix=""):
        self.path.write_text("\n".join(map(json.dumps, self.events)) + suffix,
                             encoding="utf-8")
        return read_report(self.path)

    def test_success_counts_exclude_hidden_setup_and_loading(self):
        self.start(1, "loading")
        self.finish(1, hidden=True)
        self.start(2, "布局断言")
        self.finish(2)
        self.start(3, "skipped")
        self.finish(3, skipped=True)
        self.events.append({"type": "done", "success": True, "time": 500})
        report = self.read()
        self.assertTrue(report.ok)
        self.assertEqual(dict(report.counts), {"passed": 1, "skipped": 1})
        summary = render(report, "Shard 1")
        self.assertIn("Shard 1 — PASS", summary)
        self.assertIn("test/home_test.dart", summary)
        self.assertIn("布局断言", summary)

    def test_incomplete_tail_preserves_unfinished_test(self):
        self.start(1, "横屏大字号")
        report = self.read('\n{"type": "testDone"')
        self.assertFalse(report.ok)
        self.assertEqual(report.pending, {1})
        summary = render(report, "Shard 2")
        self.assertIn("INCOMPLETE", summary)
        self.assertIn("横屏大字号", summary)
        self.assertIn("Invalid/incomplete JSON", summary)

    def test_truncated_utf8_keeps_preceding_events(self):
        self.start(1, "横屏布局")
        self.read()
        with self.path.open("ab") as output:
            output.write(b'\n{"type":"print","message":"\xe4')
        report = read_report(self.path)
        self.assertFalse(report.ok)
        self.assertEqual(report.pending, {1})
        self.assertIn("横屏布局", render(report, "Cancelled"))

    def test_hidden_loading_failure_cannot_pass(self):
        self.start(1, "loading broken_test.dart")
        self.finish(1, result="error", hidden=True)
        self.events.append({"type": "done", "success": False, "time": 200})
        report = self.read()
        self.assertFalse(report.ok)
        self.assertEqual(report.counts["failed"], 1)
        self.assertIn("loading broken_test.dart", render(report, "Shard 3"))

    def test_success_without_done_is_incomplete(self):
        self.start(1, "passes before cancelled teardown")
        self.finish(1)
        report = self.read()
        self.assertFalse(report.ok)
        self.assertIn("INCOMPLETE", render(report, "Shard 4"))

    def test_error_event_is_not_ignored(self):
        self.events.extend([
            {"type": "error", "error": "teardown failed", "time": 100},
            {"type": "done", "success": True, "time": 200},
        ])
        self.assertFalse(self.read().ok)

    def test_missing_report_is_failure(self):
        report = read_report(self.path)
        self.assertFalse(report.ok)
        self.assertTrue(report.errors)


if __name__ == "__main__":
    unittest.main()
