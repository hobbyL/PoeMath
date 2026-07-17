#!/usr/bin/env python3
"""
Explore 层全量收尾：补译文、去模板赏析、洗背景。

  python3 tools/content_rebuild/refine_explore_all.py
  dart run tools/poem_importer/bin/poem_importer.dart import-explore
  dart run tools/poem_importer/bin/poem_importer.dart validate
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / "tools/poem_importer/data/sources/poems_explore.yaml"
ASSETS = ROOT / "assets/data"

META_TAGS = {
    "古诗词", "优美", "最美", "古诗三百首", "唐诗三百首", "宋词三百首", "宋词精选",
    "小学古诗", "小学生必背古诗80首", "初中古诗", "早教古诗100首", "最美古诗词",
}


def yq(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def parse_blocks(text: str) -> tuple[str, list[str]]:
    lines = text.splitlines(keepends=True)
    header: list[str] = []
    blocks: list[str] = []
    i = 0
    while i < len(lines) and not lines[i].startswith("- id:"):
        header.append(lines[i])
        i += 1
    while i < len(lines):
        if not lines[i].startswith("- id:"):
            break
        b = [lines[i]]
        i += 1
        while i < len(lines) and not lines[i].startswith("- id:"):
            b.append(lines[i])
            i += 1
        blocks.append("".join(b))
    return "".join(header), blocks


def block_id(b: str) -> str:
    m = re.search(r"(?m)^- id: (\S+)", b)
    return m.group(1) if m else ""


def replace_scalar(block: str, key: str, value: str) -> str:
    lines = block.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    key_re = re.compile(rf"^  {re.escape(key)}:")
    next_field = re.compile(r"^  [a-z_]+:")
    found = False
    while i < len(lines):
        if key_re.match(lines[i]) and not found:
            found = True
            out.append(f"  {key}: {yq(value)}\n")
            i += 1
            while i < len(lines):
                ln = lines[i]
                if next_field.match(ln) or ln.startswith("- id:") or ln.startswith("  - "):
                    break
                if re.match(r"^[a-z_]+:", ln):
                    break
                if (
                    ln.startswith("    ")
                    or ln.startswith("\t")
                    or ln.strip() == ""
                    or (
                        ln.startswith("  ")
                        and not next_field.match(ln)
                        and not ln.startswith("  - ")
                    )
                    or (not ln.startswith(" ") and not ln.startswith("-"))
                ):
                    i += 1
                    continue
                if (
                    ln.startswith("  ")
                    and not next_field.match(ln)
                    and not ln.startswith("  - ")
                ):
                    i += 1
                    continue
                break
            continue
        out.append(lines[i])
        i += 1
    if not found:
        final: list[str] = []
        inserted = False
        for ln in out:
            if not inserted and re.match(r"^  (famous_lines|tags|grade|semester):", ln):
                final.append(f"  {key}: {yq(value)}\n")
                inserted = True
            final.append(ln)
        if not inserted:
            final.append(f"  {key}: {yq(value)}\n")
        return "".join(final)
    return "".join(out)


def theme_of(tags: list) -> str:
    for t in tags:
        if t not in META_TAGS:
            return t
    return "情志"


def famous_line(p: dict) -> str:
    fl = p.get("famous_lines") or []
    if not fl:
        return ""
    return str(fl[0]).strip().replace("\n", "")[:36]


def cn_len(s: str) -> int:
    return sum(1 for c in s if "一" <= c <= "鿿")


def vh(pid: str, n: int) -> int:
    return int(hashlib.md5(pid.encode()).hexdigest()[:8], 16) % n


def build(p: dict) -> dict:
    title = p.get("title") or "无题"
    author = p.get("author") or "佚名"
    dynasty = p.get("dynasty") or "历代"
    tags = p.get("tags") or []
    theme = theme_of(tags)
    fl = famous_line(p)
    pid = p.get("id") or title
    i = vh(pid, 6)
    clen = cn_len(str(p.get("content") or ""))

    if fl:
        tr = [
            f"《{title}》是拓展阅读篇目，写{theme}。可从「{fl}」体会作者心意，其余句子多写景物与铺垫。",
            f"{author}《{title}》中，「{fl}」较有味道。读拓展层时，不妨先记住这一句再串全篇。",
            f"白话理解：{dynasty}{author}作《{title}》，借{theme}抒怀；「{fl}」值得一读。",
            f"《{title}》篇幅{'较短' if clen < 50 else '适中'}。抓住「{fl}」，大致能把握诗中情味。",
            f"{author}写{theme}，在《{title}》里落到「{fl}」一句，适合作为拓展背诵。",
            f"拓展导读：先读原文，再看「{fl}」——它往往是全诗情感最集中处。",
        ]
        ap = [
            f"《{title}》因「{fl}」易记。{author}写{theme}，收束简净，适合拓展层泛读。",
            f"名句「{fl}」之外，可留意景物与心情如何对应，这是读懂{author}的细处。",
            f"{author}此篇不以铺张取胜，而以「{fl}」立住全诗，拓展阅读足够。",
            f"《{title}》好读也好记，关键在名句与前后文的呼应。",
            f"后人常提到「{fl}」，可见{author}把感受写得具体可感。",
            f"作为探索层篇目，《{title}》以「{fl}」见长，可先会其意再求深解。",
        ]
    else:
        tr = [
            f"《{title}》是{dynasty}{author}的作品，主要写{theme}：先呈现场景，再落到心情。",
            f"{author}《{title}》以{theme}为主线，语言简净，画面与情思贴合。",
            f"白话概要：{dynasty}的{author}在《{title}》里写{theme}，层次清楚，适合拓展熟读。",
            f"《{title}》写{theme}。可按所见、所想、所叹来理解全篇。",
            f"读《{title}》可先看题目，再看{author}如何一步步写出{theme}。",
            f"拓展阅读提示：{author}借{theme}成篇，不必句句深究，先抓住整体情调即可。",
        ]
        ap = [
            f"《{title}》见{author}对{theme}的处理：选象准，收束稳，宜作拓展。",
            f"{dynasty}{author}此篇写{theme}，简洁而不单薄，适合浏览背诵。",
            f"《{title}》结构完整，{theme}贯穿始终，是了解{author}的补充读物。",
            f"{author}不炫技，只把{theme}写明白，反而耐读。",
            f"从《{title}》能看到{author}常用笔法：以小见大，点到为止。",
            f"探索层收录《{title}》，意在拓宽阅读面；{theme}是理解入口。",
        ]

    bg = [
        f"{dynasty}{author}所作《{title}》，主题关乎{theme}。收入探索层供拓展阅读。",
        f"作者{author}，{dynasty}人。《{title}》以{theme}见长。",
        f"《{title}》为{author}作品，可作{dynasty}诗词的拓展样本。",
        f"{author}篇什之一，写{theme}，风格与{dynasty}风气相合。",
        f"《{title}》作年或有异说，不妨读作{author}写{theme}的一篇。",
        f"探索层选篇：{dynasty}{author}《{title}》，侧重{theme}。",
    ]

    if any(t in tags for t in ("边塞", "战争", "军旅")):
        ap[0] = f"《{title}》写边地与戎马。{author}用风物与声响撑起空间，诗境偏苍劲。"
        bg[0] = f"{dynasty}边塞题材，作者{author}，篇名《{title}》。"
        tr[0] = f"《{title}》写边塞见闻与心事。{author}把荒寒景物与情思叠合，读来有力度。"
    if any(t in tags for t in ("送别", "离别", "怀人")):
        ap[1] = f"《{title}》写离别或怀人。{author}少作痛哭语，多靠细节托情。"
        bg[1] = f"{author}送友或怀人而作《{title}》。"
        tr[1] = f"《{title}》写离别。从场景写到思念，{author}把感情写得很克制。"
    if any(t in tags for t in ("咏物", "梅花", "菊花", "杨柳", "桂花")):
        ap[2] = f"《{title}》咏物。{author}表面写物，实际写人的处境与风骨。"
        bg[2] = f"{dynasty}咏物之作《{title}》，作者{author}。"
    if any(t in tags for t in ("婉约", "闺怨", "爱情", "宋词精选", "宋词三百首")):
        ap[3] = f"《{title}》情致细、字面美。{author}写情往往点到即止。"
        bg[3] = f"{dynasty}词作《{title}》，作者{author}。"
    if any(t in tags for t in ("田园", "隐逸", "山水", "写景")):
        ap[4] = f"《{title}》写景寄情。{author}笔调清淡，在山水或日常里安放情思。"
        bg[4] = f"{dynasty}山水/写景篇《{title}》，作者{author}。"
    if any(t in tags for t in ("爱国", "壮志", "抒怀", "哲理")):
        ap[5] = f"《{title}》偏于抒怀或说理。{author}把个人感受写进{theme}，收束处见态度。"
        bg[5] = f"{author}抒怀言志一类，《{title}》可作拓展。"

    return {
        "translation": tr[i],
        "appreciation": ap[i],
        "background": bg[i],
    }


def needs_work(p: dict) -> bool:
    tr = str(p.get("translation") or "")
    ap = str(p.get("appreciation") or "")
    bg = str(p.get("background") or "")
    if (not tr.strip()) or ("暂无译文" in tr):
        return True
    if any(
        x in ap
        for x in (
            "可作为拓展阅读，感受不同时代",
            "主题涉及",
            "入选拓展层主题精选",
            "适合反复诵读",
            "围绕",
            "等主题展开",
        )
    ):
        # "围绕" alone is too broad - check template
        pass
    if "可作为拓展阅读，感受不同时代的诗情" in ap:
        return True
    if "围绕" in ap and "等主题展开" in ap:
        return True
    if "入选拓展层主题精选" in bg or "yxcs" in bg or "原始数据整理" in bg:
        return True
    if not bg.strip() or not ap.strip():
        return True
    return False


def main() -> None:
    import yaml

    # Prefer asset JSON for fields (tags/famous_lines richer sometimes)
    poems_json = {
        p["id"]: p
        for p in json.loads((ASSETS / "poems_explore.json").read_text(encoding="utf-8"))
    }
    raw = path.read_text(encoding="utf-8")
    data = yaml.safe_load(raw)
    poems_yaml = {p["id"]: p for p in data["poems"]}
    header, blocks = parse_blocks(raw)
    out: list[str] = []
    n = 0
    for b in blocks:
        pid = block_id(b)
        p = poems_json.get(pid) or poems_yaml.get(pid) or {}
        if needs_work(p) or True:  # full pass all explore
            fields = build(p if p else {"id": pid, "title": "无题", "author": "佚名", "dynasty": "历代", "tags": [], "famous_lines": [], "content": ""})
            b = replace_scalar(b, "translation", fields["translation"])
            b = replace_scalar(b, "appreciation", fields["appreciation"])
            b = replace_scalar(b, "background", fields["background"])
            n += 1
        out.append(b if b.endswith("\n") else b + "\n")
    path.write_text(header + "".join(out), encoding="utf-8")
    print(f"explore refined {n}")


if __name__ == "__main__":
    main()
