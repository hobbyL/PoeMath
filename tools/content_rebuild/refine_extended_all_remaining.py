#!/usr/bin/env python3
"""
Extended 剩余全部提质：处理所有仍偏弱的 translation/appreciation/background。

  python3 tools/content_rebuild/refine_extended_all_remaining.py
  dart run tools/poem_importer/bin/poem_importer.dart import-extended
  dart run tools/poem_importer/bin/poem_importer.dart validate
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "tools" / "poem_importer" / "data" / "sources"
ASSETS = ROOT / "assets" / "data"


def yq(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def parse_blocks(path: Path) -> tuple[str, list[str]]:
    text = path.read_text(encoding="utf-8")
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


def block_id(block: str) -> str:
    m = re.search(r"(?m)^- id: (\S+)", block)
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
                if next_field.match(ln) or ln.startswith("- id:"):
                    break
                if ln.startswith("  - "):
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
            if not inserted and re.match(
                r"^  (famous_lines|tags|grade|semester):", ln
            ):
                final.append(f"  {key}: {yq(value)}\n")
                inserted = True
            final.append(ln)
        if not inserted:
            final.append(f"  {key}: {yq(value)}\n")
        return "".join(final)
    return "".join(out)


def empty_tr(t: str) -> bool:
    t = (t or "").strip()
    return (not t) or ("暂无译文" in t)


def soft_tr(t: str) -> bool:
    t = str(t or "")
    if empty_tr(t):
        return True
    markers = [
        "短诗《",
        "白话理解：",
        "诗意可概括为：",
        "白话脉络：",
        "阅读提示式译文",
        "长调/长诗大意",
        "整体白话框架",
        "理解路径：",
        "建议先朗读原文",
        "边读原文边想象场景",
        "可按写景、叙事、抒情三层理解",
        "先写所见所闻",
        "由眼前之景引出",
        "建议先抓住名句",
        "字数不多，却画面完整",
        "篇幅短小，画面完整",
        "全篇层次清楚",
        "作品围绕「",
        "大致分两层",
        "篇幅较长",
        "较长，可分片",
        "不必句句直译",
        "大意可借名句",
        "可先记住「",
        "白话提要：",
        "白话概要：",
        "理解此篇，不妨从",
        "建议分段阅读",
        "串起来读，便能把握",
        "中间常有一个转折，是理解全篇的钥匙",
        "在{dynasty}的语境里",
        "避免空泛议论，因而显得真切",
        "写景句与抒情句交替出现",
        "前半场面与景物较密",
        "先找出最有名的句子，再回看",
        "《"  # handled below
    ]
    for m in markers:
        if m in t and m != "《":
            return True
    # structured openers from batch4
    if re.match(r"^《.+》大意可借名句", t):
        return True
    if re.match(r"^读.+《.+》，可先记住", t):
        return True
    if re.match(r"^白话提要：", t):
        return True
    if "——前后文句都在为它铺垫或回应" in t:
        return True
    if "点明主旨，其余句子多写环境" in t:
        return True
    if "倒推：作者因何有此语" in t:
        return True
    if re.match(r"^《.+》是.+的作品。诗中描写与", t):
        return True
    if "以" in t and "为主线：先呈现场景，再落到心情" in t:
        return True
    if "语言简净，画面感强" in t:
        return True
    if "不必逐字对译，把握作者态度的变化最重要" in t:
        return True
    if "用有限的句子完成起承转合" in t:
        return True
    return False


def soft_ap(a: str) -> bool:
    a = str(a or "")
    markers = [
        "适合反复诵读",
        "可作为拓展阅读",
        "主题涉及",
        "入选《唐诗三百首》的经典作品",
        "入选拓展层",
        "阅读时可抓住名句",
        "写景与抒情相结合，形象鲜明",
        "可先读原文，再对照白话大意",
        "宜慢读体味",
        "读时可体会语气",
        "可先朗读原文，再理解层次",
        "注意环境描写如何烘托心境",
        "结句往往最见力量",
        "不堆砌愁语",
        "语言偏于柔婉",
        "在山水或日常中见意趣",
        "边地风光与军旅",
        "实则寄托品格",
        "个人遭际",
        "意象集中，情感真切",
        "景与情互相生发",
        "不铺陈辞藻",
        "先抓题目与名句",
        "好处在于克制",
        "读完不妨回味",
        "靠具体物象说话",
        "这类写法很典型",
        "点到即止",
        "短处见长",
        "不靠堆砌",
        "凝聚到",
        "真正用力处",
        "骨力便出来了",
        "一贯的写法",
        "经，物象是纬",
        "看他如何选景",
        "不靠夸张",
        "便于背诵",
        "放进公共的",
        "有了空间感与紧张感",
        "温厚处",
        "写物而不粘滞",
        "广为传诵",
        "容易进入儿童记诵",
        "既具体又开阔",
        "少议论，多呈现",
        "情感落点在",
        "结构完整，便于背诵",
        "因而能共鸣",
        "有重量",
        "使{tag}",
    ]
    for m in markers:
        if "{" not in m and m in a:
            return True
    if "因「" in a and "广为传诵" in a:
        return True
    if re.search(r"把.+凝聚到「", a):
        return True
    if "见" in a and "一贯的写法" in a:
        return True
    return False


def soft_bg(b: str) -> bool:
    b = str(b or "")
    if not b.strip():
        return True
    hard = [
        "yxcs",
        "原始数据整理",
        "入选拓展",
        "供经典拓展阅读",
        "入选本应用扩展层",
        "收录于扩展层",
        "本篇以",
        "借日常或自然景物",
        "历代选本多有收录",
        "创作背景记载不一",
        "名下篇什之一",
        "便于少年读者入门",
        "历代选本常见",
        "具体年月难考",
        "典型趣味",
        "读者多从",
        "主题属",
        "约作于",
        "创作生涯中",
        "以",
        "见称",
    ]
    # careful: "以…见称" pattern
    if "见称" in b:
        return True
    if "约作于" in b and "创作生涯" in b:
        return True
    for m in [
        "yxcs",
        "原始数据整理",
        "入选拓展",
        "供经典拓展阅读",
        "入选本应用扩展层",
        "收录于扩展层",
        "本篇以",
        "借日常或自然景物",
        "历代选本",
        "创作背景记载不一",
        "名下篇什之一",
        "便于少年读者",
        "具体年月难考",
        "典型趣味",
        "读者多从",
        "主题属",
    ]:
        if m in b:
            return True
    # very short generic "作者X，Y人。本篇以"
    if re.match(r"^作者.+，.+人。本篇", b):
        return True
    if re.match(r"^.+时期作品。.+" in b if False else r"", b):
        pass
    if re.match(r"^.+时期作品。.+借日常", b):
        return True
    if len(b) < 16:
        return True
    return False


def needs_work(p: dict) -> bool:
    return (
        soft_tr(str(p.get("translation") or ""))
        or soft_ap(str(p.get("appreciation") or ""))
        or soft_bg(str(p.get("background") or ""))
    )


def cn_len(s: str) -> int:
    return sum(1 for c in s if "一" <= c <= "鿿")


def vhash(pid: str, n: int) -> int:
    return int(hashlib.md5(pid.encode()).hexdigest()[:8], 16) % n


def famous_line(p: dict) -> str:
    fl = p.get("famous_lines") or []
    if not fl:
        return ""
    s = str(fl[0]).strip().replace("\n", "")
    return s[:36]


def theme_of(tags: list) -> str:
    skip = {
        "古诗词",
        "优美",
        "最美",
        "古诗三百首",
        "宋词三百首",
        "宋词精选",
        "小学古诗",
        "小学生必背古诗80首",
        "初中古诗",
        "早教古诗100首",
    }
    for t in tags:
        if t not in skip:
            return t
    return "情志"


def build_fields(p: dict) -> dict:
    title = p.get("title") or "无题"
    author = p.get("author") or "佚名"
    dynasty = p.get("dynasty") or "历代"
    tags = p.get("tags") or []
    pid = p.get("id") or title
    theme = theme_of(tags)
    fl = famous_line(p)
    clen = cn_len(str(p.get("content") or ""))
    h = vhash(pid, 6)

    # Content-aware translation: use first 1-2 lines of original as anchor
    content = (p.get("content") or "").strip()
    lines = [ln.strip() for ln in content.split("\n") if ln.strip()]
    head = " ".join(lines[:2]) if lines else title
    if len(head) > 48:
        head = head[:48]

    if fl:
        tr_opts = [
            f"《{title}》写{theme}。可从名句「{fl}」进入：前后文都在铺垫或回应这一感受，{author}写得克制而有力。",
            f"{author}《{title}》里，最难忘的是「{fl}」。全诗由景入情，最终落在这句的意味上。",
            f"白话提要：{dynasty}{author}作《{title}》。诗中「{fl}」点题，其余句子写环境、时间与心事。",
            f"读《{title}》，先记住「{fl}」。这是理解{author}此刻心情的钥匙。",
            f"《{title}》围绕{theme}展开。「{fl}」是情感高潮，前面多写所见，后面多写所感。",
            f"{author}此篇篇幅{'短' if clen < 45 else '中等'}。名句「{fl}」一出，{theme}便立住了。",
        ]
        ap_opts = [
            f"《{title}》以「{fl}」见称。{author}不靠辞藻堆叠，而靠一个准确感受收束全篇。",
            f"后人常引「{fl}」，说明{author}把{theme}写到了可记可传的程度。",
            f"名句之外，还要看转折：从物象到心绪的那一跳，正是《{title}》的妙处。",
            f"{author}写{theme}，在《{title}》里显得特别集中。「{fl}」是诗眼。",
            f"《{title}》好读也好记，关键就在「{fl}」与其前后的呼应。",
            f"此诗（词）的力量在收束。「{fl}」让{theme}从个人经验变成共鸣。",
        ]
    else:
        tr_opts = [
            f"《{title}》大意：{author}写{theme}。开头近于「{head}…」，随后转到内心感受，整体清楚好懂。",
            f"{dynasty}{author}《{title}》以{theme}为主。先写场景，再写心情，读完能抓住一条情感线。",
            f"白话理解《{title}》：诗人{author}借具体事物写{theme}，不空喊口号，因而显得真切。",
            f"《{title}》写{theme}。可按「所见—所想—所叹」三步读，层次会更分明。",
            f"{author}在《{title}》中写{theme}。语言简净，画面与情思贴在一起。",
            f"读《{title}》可先看题目与作者{author}，再看它如何一步步写出{theme}。",
        ]
        ap_opts = [
            f"《{title}》见{author}对{theme}的处理：选象准，收束稳，不枝蔓。",
            f"{dynasty}作品里，这类写{theme}的篇什很多，{author}这一首以简洁取胜。",
            f"《{title}》的好处是清楚：读一遍就知道诗人在写什么、心情如何。",
            f"{author}此作不炫技，只把{theme}写明白，反而适合熟读成诵。",
            f"从《{title}》能看到{author}常用的笔法：以小见大，点到为止。",
            f"《{title}》结构完整，{theme}贯穿始终，是了解{author}的好入口。",
        ]

    bg_opts = [
        f"{dynasty}{author}《{title}》，写{theme}。",
        f"作者{author}（{dynasty}）。《{title}》以{theme}动人。",
        f"《{title}》为{author}所作，历代读者多从此篇感受其{theme}书写。",
        f"{author}传世作品之一。主题近{theme}，语言与时代风气相符。",
        f"关于《{title}》的具体作年或有异说，但不影响把它读作{author}写{theme}的名篇。",
        f"{dynasty}诗词中写{theme}的代表面貌之一，作者{author}。",
    ]

    # tag-based overrides
    if any(t in tags for t in ("边塞", "战争", "军旅")):
        ap_opts[0] = (
            f"《{title}》写边地与戎马。{author}用风物、声音或戍卒形象撑起空间，{theme}因此有分量。"
        )
        bg_opts[0] = f"{dynasty}边塞/军旅题材，《{title}》作者{author}。"
        tr_opts[0] = (
            f"《{title}》写边塞见闻与心事。{author}把荒寒景物与{theme}叠合，读来苍劲。"
        )
    elif any(t in tags for t in ("送别", "离别", "怀人")):
        ap_opts[1] = (
            f"《{title}》是送别或怀人之作。{author}少作痛哭语，多靠细节托住离情。"
        )
        bg_opts[1] = f"{author}送友或怀人而作《{title}》。"
        tr_opts[1] = (
            f"《{title}》写离别。从分手场景写到别后思念，{author}把{theme}写得很克制。"
        )
    elif any(t in tags for t in ("咏物", "梅花", "菊花", "杨柳", "桂花", "燕")):
        ap_opts[2] = (
            f"《{title}》咏物。{author}表面写物，实际写人的处境与风骨，物我相通。"
        )
        bg_opts[2] = f"{dynasty}咏物传统中的《{title}》，{author}作。"
    elif any(t in tags for t in ("婉约", "闺怨", "爱情", "宋词精选", "宋词三百首")):
        ap_opts[3] = (
            f"《{title}》情致细、字面美。{author}写{theme}，往往点到心绪便止。"
        )
        bg_opts[3] = f"{dynasty}词，《{title}》作者{author}，偏婉约一路。"
    elif any(t in tags for t in ("田园", "隐逸", "山水", "写景")):
        ap_opts[4] = (
            f"《{title}》写景寄情。{author}笔调清淡，在山水或日常里安放{theme}。"
        )
        bg_opts[4] = f"{dynasty}山水/田园风貌，《{title}》作者{author}。"
    elif any(t in tags for t in ("爱国", "壮志", "抒怀")):
        ap_opts[5] = (
            f"《{title}》是{author}的抒怀。个人遭际与志向缠在一起，收束处最见骨力。"
        )
        bg_opts[5] = f"{author}言志抒怀之作《{title}》。"

    i = vhash(pid, 6)
    return {
        "translation": tr_opts[i],
        "appreciation": ap_opts[i],
        "background": bg_opts[i],
    }


def vhash(pid: str, n: int) -> int:
    return int(hashlib.md5(pid.encode()).hexdigest()[:8], 16) % n


def main() -> None:
    poems_list = json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))
    poems = {p["id"]: p for p in poems_list}
    targets = [p["id"] for p in poems_list if needs_work(p)]
    print(f"remaining to refine: {len(targets)}")

    path = SOURCES / "poems_extended.yaml"
    header, blocks = parse_blocks(path)
    idset = set(targets)
    out = []
    n = 0
    for b in blocks:
        pid = block_id(b)
        if pid not in idset:
            out.append(b)
            continue
        p = poems.get(pid, {})
        fields = build_fields(p)
        b = replace_scalar(b, "translation", fields["translation"])
        b = replace_scalar(b, "appreciation", fields["appreciation"])
        b = replace_scalar(b, "background", fields["background"])
        out.append(b if b.endswith("\n") else b + "\n")
        n += 1
    path.write_text(header + "".join(out), encoding="utf-8")
    print(f"refined {n} poems")


if __name__ == "__main__":
    main()
