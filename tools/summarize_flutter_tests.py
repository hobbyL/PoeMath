#!/usr/bin/env python3
"""Summarize Flutter JSON events, including incomplete runs after a timeout."""

import argparse
from collections import Counter
from dataclasses import dataclass, field
from html import escape
import json
from pathlib import Path


@dataclass
class Report:
    tests: dict = field(default_factory=dict)
    suites: dict = field(default_factory=dict)
    finished: dict = field(default_factory=dict)
    errors: list = field(default_factory=list)
    elapsed_ms: int = 0
    success: bool = False
    complete: bool = False

    @property
    def counts(self) -> Counter:
        counts = Counter()
        for result in self.finished.values():
            if result["result"] != "success":
                counts["failed"] += 1
            elif not result.get("hidden", False):
                counts["skipped" if result.get("skipped") else "passed"] += 1
        return counts

    @property
    def pending(self) -> set:
        return self.tests.keys() - self.finished.keys()

    @property
    def ok(self) -> bool:
        return (self.complete and self.success and not self.errors
                and not self.pending and not self.counts["failed"])


def read_report(path: Path) -> Report:
    report = Report()
    try:
        # Cancellation can truncate a UTF-8 character in the last event.
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as error:
        report.errors.append(str(error))
        return report
    for number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            # A cancelled process can leave its last event partially written.
            report.errors.append(f"Invalid/incomplete JSON event at line {number}")
            continue
        report.elapsed_ms = max(report.elapsed_ms, event.get("time", 0))
        kind = event["type"]
        if kind == "suite":
            report.suites[event["suite"]["id"]] = event["suite"]["path"]
        elif kind == "testStart":
            report.tests[event["test"]["id"]] = {**event["test"],
                                                  "started": event["time"]}
        elif kind == "testDone":
            report.finished[event["testID"]] = event
        elif kind == "error":
            report.errors.append(event["error"])
        elif kind == "done":
            report.complete = True
            report.success = event["success"] is True
    return report


def render(report: Report, title: str) -> str:
    counts = report.counts
    status = "PASS" if report.ok else "FAIL" if report.complete else "INCOMPLETE"
    lines = [f"## {escape(title)} — {status}", "",
             f"Passed: {counts['passed']} · Failed: {counts['failed']} · "
             f"Skipped: {counts['skipped']} · Unfinished: {len(report.pending)}",
             f"Last recorded event: {report.elapsed_ms / 1000:.1f}s", ""]

    def entry(test_id, elapsed):
        test = report.tests[test_id]
        path = report.suites.get(test["suiteID"], "")
        # Shorten runner-specific absolute paths without assuming the checkout.
        if "/test/" in path:
            path = "test/" + path.split("/test/", 1)[1]
        return (f"- {elapsed / 1000:.2f}s · <code>{escape(path)}</code> · "
                f"{escape(test['name'])}")

    if report.pending:
        lines.extend(["### Started but unfinished", ""])
        for test_id in sorted(report.pending):
            lines.append(entry(test_id, report.elapsed_ms
                               - report.tests[test_id]["started"]))
        lines.append("")
    failures = [test_id for test_id, result in report.finished.items()
                if result["result"] != "success"]
    if failures:
        lines.extend(["### Failed tests (including loading / teardown)", ""])
        for test_id in failures:
            lines.append(entry(test_id, report.finished[test_id]["time"]
                               - report.tests[test_id]["started"]))
        lines.append("")
    durations = sorted((
        (result["time"] - report.tests[test_id]["started"], test_id)
        for test_id, result in report.finished.items()
        if not result.get("hidden") and not result.get("skipped")
    ), reverse=True)
    if durations:
        lines.extend(["### Slowest completed tests", ""])
        lines.extend(entry(test_id, elapsed) for elapsed, test_id in durations[:10])
        lines.append("")
    if report.errors:
        lines.extend(["### Report / test errors", ""])
        lines.extend(f"<pre>{escape(error[:2000])}</pre>"
                     for error in report.errors[:10])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--title", default="Flutter tests")
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()
    report = read_report(args.report)
    summary = render(report, args.title)
    print(summary)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as output:
            output.write(summary)
    return 0 if report.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
