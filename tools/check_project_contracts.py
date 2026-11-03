"""Check SDK pin and consistency of the optional local privacy-policy mirror."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLUTTER_VERSION = "3.47.8"
DART_VERSION = "3.13.7"


def check():
    version = json.loads((ROOT / ".fvmrc").read_text())["flutter"]
    if version != FLUTTER_VERSION:
        raise ValueError(f"FVM 必须固定 Flutter {FLUTTER_VERSION}")
    for workflow in (ROOT / ".github/workflows").glob("*.yml"):
        if f"flutter-version: '{version}'" not in workflow.read_text():
            raise ValueError(f"CI Flutter 版本与 FVM 不一致：{workflow.name}")
    pubspec = (ROOT / "pubspec.yaml").read_text()
    if f'sdk: ">={DART_VERSION} <4.0.0"' not in pubspec:
        raise ValueError("Dart SDK 下限必须包含 TLS 安全修复")
    if f'flutter: ">={FLUTTER_VERSION}"' not in pubspec:
        raise ValueError("Flutter SDK 下限必须包含 TLS 安全修复")
    source = (ROOT / "assets/legal/privacy_policy.md").read_text()
    mirror = ROOT / "docs/PRIVACY.md"
    if mirror.exists() and mirror.read_text() != source:
        raise ValueError("本地隐私政策副本与 assets/legal/privacy_policy.md 不一致")


if __name__ == "__main__":
    check()
