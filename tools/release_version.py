"""One tag parser for Android builds and update history."""
import argparse
import re
import subprocess
from pathlib import Path

VERSION = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def parse_tag(tag):
    match = VERSION.fullmatch(tag)
    if not match:
        raise ValueError("tag 必须为 v主版本.次版本.修订号，且不能有前导零")
    major, minor, patch = map(int, match.groups())
    if minor >= 100 or patch >= 100:
        raise ValueError("次版本和修订号必须小于 100，避免构建号碰撞")
    code = major * 10000 + minor * 100 + patch
    if not 1 <= code <= 2100000000:
        raise ValueError("构建号超出发布兼容范围")
    return tag[1:], code


def validate_release(tag, history):
    name, code = parse_tag(tag)
    for old in history:
        if old == tag:
            continue
        try:
            _, previous = parse_tag(old)
        except ValueError:
            # Earlier builds accepted out-of-range minor/patch and leading zeros.
            # Their published versionCode still occupies the old numeric slot.
            legacy = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", old)
            if not legacy:
                continue
            major, minor, patch = map(int, legacy.groups())
            previous = major * 10000 + minor * 100 + patch
        if previous >= code:
            raise ValueError(f"构建号必须高于已发布 tag {old} ({previous})")
    return name, code


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("tag")
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    history = subprocess.run(["git", "tag", "--list", "v*"],
                             check=True, capture_output=True, text=True).stdout.splitlines()
    name, code = validate_release(args.tag, history)
    output = f"version_name={name}\nversion_code={code}\ntag={args.tag}\n"
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as file:
            file.write(output)
    print(output, end="")


if __name__ == "__main__":
    main()
