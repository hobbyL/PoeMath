"""Check SDK pin and consistency of the optional local privacy-policy mirror."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check():
    version = json.loads((ROOT / ".fvmrc").read_text())["flutter"]
    if version != "3.44.6":
        raise ValueError("FVM 必须固定 Flutter 3.44.6")
    for workflow in (ROOT / ".github/workflows").glob("*.yml"):
        if "flutter-version: '3.44.6'" not in workflow.read_text():
            raise ValueError(f"CI Flutter 版本与 FVM 不一致：{workflow.name}")
    source = (ROOT / "assets/legal/privacy_policy.md").read_text()
    mirror = ROOT / "docs/PRIVACY.md"
    if mirror.exists() and mirror.read_text() != source:
        raise ValueError("本地隐私政策副本与 assets/legal/privacy_policy.md 不一致")


if __name__ == "__main__":
    check()
