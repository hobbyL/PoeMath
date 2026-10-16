#!/usr/bin/env python3
"""Check minimum Android API declarations against the app's Gradle configuration."""

import argparse
from pathlib import Path
import re
import sys


def read_declaration(root, relative_path, pattern, errors):
    """Require one unambiguous declaration and return its numeric API level."""
    try:
        content = (root / relative_path).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        errors.append(f"{relative_path}: 无法读取文件：{error}")
        return None
    matches = re.findall(pattern, content, re.MULTILINE)
    if len(matches) != 1:
        errors.append(f"{relative_path}: 必须有且仅有一处最低版本声明，找到 {len(matches)} 处")
        return None
    return int(matches[0])


def check(root):
    errors = []
    source = "android/app/build.gradle"
    expected = read_declaration(
        root, source, r"^\s*minSdk\s*=\s*(\d+)\s*(?://[^\n]*)?$", errors
    )
    declarations = [
        (
            "flutter_launcher_icons.yaml",
            r"^\s*min_sdk_android:\s*(\d+)\s*(?:#[^\n]*)?$",
        ),
        (
            "README.md",
            r"^(?:- )?Android 最低版本：Android [\d.]+（API (\d+)）\s*$",
        ),
    ]
    # These developer guides are intentionally ignored by Git. Check them locally
    # when present, but allow CI checkouts that contain only versioned files.
    for relative_path in ("AGENTS.md", "docs/android-emulator-dev.md"):
        if (root / relative_path).exists():
            declarations.append(
                (
                    relative_path,
                    r"^(?:- )?Android 最低版本：Android [\d.]+（API (\d+)）\s*$",
                )
            )
    for relative_path, pattern in declarations:
        actual = read_declaration(root, relative_path, pattern, errors)
        if expected is not None and actual is not None and actual != expected:
            errors.append(
                f"{relative_path}: API {actual} 与 {source} 的 API {expected} 不一致"
            )
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Android 最低版本一致性检查通过：API {expected}（{len(declarations) + 1} 个文件）")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Project root (defaults to this script's repository)",
    )
    args = parser.parse_args()
    return check(args.project_root)


if __name__ == "__main__":
    sys.exit(main())
