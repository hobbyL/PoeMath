#!/usr/bin/env python3
"""Run one deterministic, disjoint slice of the Flutter test files."""

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def select_files(root: Path, shard_index: int, total_shards: int) -> list[str]:
    if total_shards < 1 or not 0 <= shard_index < total_shards:
        raise ValueError("shard index must be in [0, total shards)")
    files = sorted(path.relative_to(root).as_posix()
                   for path in (root / "test").rglob("*_test.dart"))
    selected = files[shard_index::total_shards]
    if not selected:
        raise ValueError(f"shard {shard_index} contains no test files")
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shard-index", type=int, required=True)
    parser.add_argument("--total-shards", type=int, required=True)
    parser.add_argument("--concurrency", type=int, default=2)
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--report-dir", type=Path,
                        default=Path("build/test-results"))
    args = parser.parse_args()
    if args.concurrency < 1:
        parser.error("concurrency must be positive")
    try:
        files = select_files(ROOT, args.shard_index, args.total_shards)
    except ValueError as error:
        parser.error(str(error))
    report_dir = ROOT / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)
    # Keep the exact selection even when the test process is interrupted.
    (report_dir / "test-files.txt").write_text("\n".join(files) + "\n",
                                              encoding="utf-8")
    # Compilation may fail before Flutter opens its reporter. Do not summarize
    # a previous successful run left in the same local output directory.
    report_path = report_dir / "flutter-tests.json"
    report_path.write_text("", encoding="utf-8")
    print(f"Shard {args.shard_index + 1}/{args.total_shards}: "
          f"{len(files)} test files, concurrency {args.concurrency}", flush=True)
    return subprocess.run([
        args.flutter, "test", "--no-pub", "--reporter=expanded",
        f"--concurrency={args.concurrency}",
        "--file-reporter", f"json:{report_path}",
        *files,
    ], cwd=ROOT, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
