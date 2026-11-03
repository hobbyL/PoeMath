"""Reject vulnerable PDFium dependencies and resolved native build inputs."""
import json
from pathlib import Path
import re
from urllib.parse import unquote, urljoin, urlparse
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parents[1]
# chromium/8100 is the first pdfium-binaries release containing the fix for
# CVE-2026-110155; the pinned package below bundles chromium/8125.
MINIMUM_PDFIUM_BRANCH = 8100
SAFE_PACKAGE_FLOORS = {
    "pdfrx": (2, 11, 0),
    "pdfrx_engine": (0, 9, 0),
    "pdfium_dart": (0, 4, 1),
    "pdfium_flutter": (0, 4, 1),
}


def _version(value):
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError(f"PDF 依赖必须使用稳定版本：{value}")
    return tuple(int(part) for part in value.split("."))


def _locked_version(lock, name):
    block = re.search(
        rf"^  {re.escape(name)}:\n(.*?)(?=^  \S|\Z)", lock, re.M | re.S
    )
    version = None if block is None else re.search(
        r'^    version: "([^"\n]+)"$', block.group(1), re.M
    )
    if version is None:
        raise ValueError(f"pubspec.lock 缺少 PDF 依赖版本：{name}")
    return version.group(1)


def _package_roots(config_file):
    if not config_file.exists():
        raise ValueError("请先运行 flutter pub get，再检查实际解析的 PDF 依赖")
    config = json.loads(config_file.read_text())
    result = {}
    for package in config["packages"]:
        uri = urlparse(urljoin(config_file.resolve().as_uri(), package["rootUri"]))
        if uri.scheme == "file":
            result[package["name"]] = Path(url2pathname(uri.path))
    return result


def _require_safe_branch(branch, source):
    if branch is None or int(branch) < MINIMUM_PDFIUM_BRANCH:
        raise ValueError(f"{source} 未包含 PDFium 安全修复（至少 chromium/8100）")


def check():
    lock = (ROOT / "pubspec.lock").read_text()
    packages = _package_roots(ROOT / ".dart_tool/package_config.json")
    for name, floor in SAFE_PACKAGE_FLOORS.items():
        locked = _locked_version(lock, name)
        if _version(locked) < floor:
            raise ValueError(f"PDF 依赖版本包含已知漏洞：{name} {locked}")
        package = packages.get(name)
        if package is None:
            raise ValueError(f"实际解析的 PDF 依赖缺失：{name}")
        installed = re.search(
            r"^version:\s*([^\s]+)\s*$", (package / "pubspec.yaml").read_text(), re.M
        )
        if installed is None or installed.group(1) != locked:
            raise ValueError(f"实际 PDF 依赖与锁文件不一致：{name}")

    hook = (packages["pdfium_dart"] / "hook/build.dart").read_text()
    release = re.search(r"_pdfiumRelease\s*=\s*['\"]([^'\"]+)['\"]", hook)
    branch = None if release is None else re.fullmatch(
        r"chromium/(\d+)", unquote(release.group(1))
    )
    _require_safe_branch(None if branch is None else branch.group(1), "原生构建 hook")

    podspec = (packages["pdfium_flutter"] / "darwin/pdfium_flutter.podspec").read_text()
    apple_branch = re.search(r"PDFium-chromium-(\d+)-", podspec)
    _require_safe_branch(
        None if apple_branch is None else apple_branch.group(1), "Apple 原生库"
    )


if __name__ == "__main__":
    check()
    print("PDFium 依赖、安全版本与原生构建输入检查通过")
