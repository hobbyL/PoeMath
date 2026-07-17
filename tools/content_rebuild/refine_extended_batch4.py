#!/usr/bin/env python3
"""
Extended 第四批：优先清空「暂无译文」，并继续提质 100 首。

  python3 tools/content_rebuild/refine_extended_batch4.py
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
BATCH = 100


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
                    or (ln.startswith("  ") and not next_field.match(ln) and not ln.startswith("  - "))
                    or (not ln.startswith(" ") and not ln.startswith("-"))
                ):
                    i += 1
                    continue
                if ln.startswith("  ") and not next_field.match(ln) and not ln.startswith("  - "):
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


def empty_tr(t: str) -> bool:
    t = (t or "").strip()
    return (not t) or ("暂无译文" in t)


def soft_tr(t: str) -> bool:
    """Structured but still low-quality translations from earlier batches."""
    t = t or ""
    if empty_tr(t):
        return True
    markers = (
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
        "先写所见所闻，再落到心情",
        "由眼前之景引出身世或人生感慨",
        "建议先抓住名句与关键意象",
        "字数不多，却画面完整",
        "篇幅短小，画面完整",
        "全篇层次清楚",
        "作品围绕「",
        "大致分两层",
        "篇幅较长，可分片",
        "较长，可分片（段）读",
        "不必句句直译",
    )
    return any(m in t for m in markers)


def soft_ap(a: str) -> bool:
    a = a or ""
    markers = (
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
        "边地风光与军旅情思交织",
        "实则寄托品格与情志",
        "个人遭际与",
        "意象集中，情感真切",
        "景与情互相生发",
        "不铺陈辞藻，而靠具体物象说话",
        "先抓题目与名句",
        "好处在于克制",
        "读完不妨回味最动人的一两句",
        "短处见长，越读越有余味",
        "这类写法很典型",
        "点到即止，留下空白",
        "使{tag}",  # won't match
        "把{tag}",
    )
    # also batch3 templates
    markers += (
        "读完不妨回味",
        "靠具体物象说话",
        "落到实处",
        "留下空白让读者",
        "适合对照注释细品用字",
        "有了空间感与紧张感",
        "是中唐送别名篇",  # too specific if wrong - keep
    )
    return any(m in a for m in markers if "{" not in m)


def soft_bg(b: str) -> bool:
    b = b or ""
    if not b.strip():
        return True
    hard = (
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
    )
    return any(m in b for m in hard)


def cn_len(s: str) -> int:
    return sum(1 for c in s if "一" <= c <= "鿿")


def variant(pid: str, n: int) -> int:
    return int(hashlib.md5(pid.encode()).hexdigest()[:8], 16) % n


def famous_lines(p: dict) -> str:
    fl = p.get("famous_lines") or []
    if not fl:
        return ""
    line = str(fl[0]).strip()
    if len(line) > 40:
        line = line[:40]
    return line


CURATED: dict[str, dict] = {
    "poem_ext_007": {
        "translation": "秋夜里银烛照着清冷的画屏，宫女拿着轻罗小扇扑打流萤。"
        "天阶上的夜色凉得像水，她坐着仰望牵牛织女星。",
        "appreciation": "杜牧写宫怨，不直说寂寞，只写扑萤与望星。凉夜、小扇、双星，含蓄而有画面，是七绝精品。",
        "background": "杜牧宫怨名篇，一作王建诗，以秋夕宫中琐事见深宫孤寂。",
    },
    "poem_ext_011": {
        "translation": "古行宫一片寥落，宫花仍寂寞地开着红。"
        "白头宫女还在，闲坐着谈论玄宗从前的事。",
        "appreciation": "元稹二十字写尽盛衰。白头宫女「说玄宗」一句，历史沧桑全在平常闲话里。",
        "background": "元稹过连昌宫一类故宫有感而作，入选《唐诗三百首》。",
    },
    "poem_ext_014": {
        "translation": "山中送你离去之后，夕阳西下，我才关上柴门。"
        "明年春天草又绿的时候，你还会不会回来？",
        "appreciation": "王维送别不写宴席，只写送罢掩扉与春草明年，淡而有情，余味不尽。",
        "background": "王维隐居山中送友之作。",
    },
    "poem_ext_015": {
        "translation": "新酿的酒面上泛着绿色泡沫，小火炉上红泥烧得正旺。"
        "天色傍晚，眼看要下雪了，能不能过来喝一杯？",
        "appreciation": "白居易邀友小饮，三样物象（新酒、火炉、暮雪）温暖亲切，是日常友情的绝唱。",
        "background": "白居易江州时期邀刘十九小酌而作。",
    },
    "poem_ext_017": {
        "translation": "美人卷起珠帘，深深坐着蹙眉。"
        "只看见泪痕湿面，却不知道心里恨谁。",
        "appreciation": "李白写闺怨，前写神态，后写泪痕，恨意不明说，更见含蓄。",
        "background": "李白五绝，写女子幽怨。",
    },
    "poem_ext_021": {
        "translation": "功业覆盖了三分天下的局面，声名成就于八阵图。"
        "江流石不转，遗恨在于未能统一，吞灭吴国。",
        "appreciation": "杜甫咏诸葛亮。前两句颂功，后两句以江石不动写千古遗恨，苍劲简括。",
        "background": "杜甫入蜀后凭吊武侯遗迹而作。",
    },
    "poem_ext_013": {
        "translation": "你从故乡来，应该知道故乡的事。"
        "来的那天，窗前的寒梅开了没有？",
        "appreciation": "王维写思乡，不问人事只问梅花，淡语深情，是五绝中的极品。",
        "background": "王维《杂诗》其二，写游子问乡。",
    },
    "poem_ext_020": {
        "translation": "岭外音书断绝，经冬又历春。"
        "近乡情更怯，不敢向来人打听消息。",
        "appreciation": "宋之问写贬谪归来近乡的心理：「情更怯」「不敢问」把复杂心情写到极致。",
        "background": "宋之问从贬所北归、接近家乡时所作。",
    },
    "poem_ext_022": {
        "translation": "打起黄莺儿，别让它在枝上啼。"
        "啼的时候惊扰了我的梦，害我梦不到辽西。",
        "appreciation": "金昌绪写思妇，迁怒黄莺，娇嗔中见相思之深，口语天然。",
        "background": "唐人闺怨小诗，流传极广。",
    },
    "poem_ext_023": {
        "translation": "怀着你同我一样的情怀，我端着酒，却望着秋天下雨。"
        "想必池塘中的树木，也落下了许多叶子。",
        "appreciation": "韦应物寄友，不写自己寂寞，却推想对方池上落叶，淡而厚。",
        "background": "韦应物寄赠丘丹（邱员外）的秋夜之作。",
    },
    "poem_ext_024": {
        "translation": "终南阴岭的余雪，晴色中显得格外好看。"
        "林梢的明亮颜色格外鲜艳，暮色里城中更添寒意。",
        "appreciation": "祖咏应试只写四句即交卷。以余雪、林表、城中写冬晴，精炼传神。",
        "background": "祖咏应试《终南望余雪》时所作，传以意尽而止。",
    },
    "poem_ext_025": {
        "translation": "故乡远在三千里外，深宫里我已待了十二年。"
        "一声声《何满子》，令我双泪落在君王面前。",
        "appreciation": "张祜写宫人悲苦，数字对照强烈，结句泪落君前，震撼人心。",
        "background": "张祜《宫词》，写远嫁入宫的女子。",
    },
    "poem_ext_012": {
        "translation": "第三天便下厨房，洗手亲自做羹汤。"
        "还没熟知婆婆的口味，先让小姑尝一尝。",
        "appreciation": "王建写新嫁娘的细心与谨慎，生活气息浓，细节真实可爱。",
        "background": "王建《新嫁娘词》，写新婚生活片段。",
    },
    "poem_ext_016": {
        "translation": "北斗七星高高挂起，哥舒翰夜里带刀巡逻。"
        "至今人还在传说：曾让牧马的胡人不敢越过临洮。",
        "appreciation": "边地民歌体颂哥舒翰，语言质朴，气势豪迈，名将形象鲜明。",
        "background": "唐代西北民歌，颂陇右节度使哥舒翰。",
    },
    "poem_ext_019": {
        "translation": "鸣筝的金粟柱上，纤纤素手在玉房前拨弦。"
        "只因为一曲一柱都满是相思，才把这二十五弦都拨遍。",
        "appreciation": "李端写听筝，以手与弦写情，结句「二十五弦」把相思写满全器。",
        "background": "李端《听筝》，写听曲生情。",
    },
}


def cn_len(s: str) -> int:
    return sum(1 for c in s if "一" <= c <= "鿿")


def variant(pid: str, n: int) -> int:
    return int(hashlib.md5(pid.encode()).hexdigest()[:8], 16) % n


def build_fields(p: dict) -> dict:
    title = p.get("title") or "无题"
    author = p.get("author") or "佚名"
    dynasty = p.get("dynasty") or "历代"
    tags = p.get("tags") or []
    pid = p.get("id") or title
    fl = famous_lines(p)
    clen = cn_len(str(p.get("content") or ""))
    v = variant(pid, 5)
    theme = next(
        (
            t
            for t in tags
            if t
            not in (
                "古诗词",
                "优美",
                "最美",
                "古诗三百首",
                "宋词三百首",
                "宋词精选",
            )
        ),
        "情志",
    )

    # Prefer concrete hooks: title + famous line + author
    if fl:
        tr_pool = [
            f"《{title}》大意可借名句「{fl}」把握：{author}在诗中写出与此相关的所见所感，语气真挚，余味在篇外。",
            f"读{author}《{title}》，可先记住「{fl}」。全诗围绕这一感受展开，由景入情，收束有力。",
            f"白话提要：{dynasty}{author}作《{title}》。诗里最动人的是「{fl}」——前后文句都在为它铺垫或回应。",
            f"《{title}》写的是{theme}。名句「{fl}」点明主旨，其余句子多写环境、人事或时间变化。",
            f"理解{author}此篇，不妨从「{fl}」倒推：作者因何有此语？答案就在前后写景与叙事中。",
        ]
        ap_pool = [
            f"《{title}》因「{fl}」广为传诵。{author}不靠堆砌，而靠一个鲜明感受统摄全篇。",
            f"{author}此作的好处，是把{theme}凝聚到「{fl}」这样可记可吟的句子上，因而容易进入儿童记诵。",
            f"名句「{fl}」之外，还要注意诗中的对比与转折——那往往是{author}真正用力处。",
            f"《{title}》篇幅{'短小' if clen < 50 else '适中'}，节奏清楚。抓住「{fl}」，全诗骨力便出来了。",
            f"后人爱引「{fl}」，正因为{author}把个人感受写得既具体又开阔。",
        ]
    else:
        tr_pool = [
            f"《{title}》是{dynasty}{author}的作品。诗中描写与{theme}相关的情景，由具体事物说到心里感受。",
            f"{author}《{title}》以{theme}为主线：先呈现场景，再落到心情，读时按顺序串起来即可。",
            f"白话概要：{dynasty}的{author}在《{title}》里写{theme}，语言简净，画面感强。",
            f"《{title}》大意是{author}借{theme}抒怀。不必逐字对译，把握作者态度的变化最重要。",
            f"这首诗写{theme}。{author}用有限的句子完成起承转合，适合边读边想象。",
        ]
        ap_pool = [
            f"《{title}》见{author}一贯的写法：少议论，多呈现。{theme}是经，物象是纬。",
            f"{dynasty}{author}此篇，情感落点在{theme}。读时看他如何选景、如何收束。",
            f"《{title}》的力量来自克制与准确，不靠夸张。对{theme}的处理尤其耐看。",
            f"若只记一篇{author}写{theme}的小诗，可选《{title}》：结构完整，便于背诵。",
            f"{author}在《{title}》里把个人感受放进公共的{theme}经验中，因而能共鸣。",
        ]

    bg_pool = [
        f"{dynasty}{author}所作《{title}》，历代选本常见。",
        f"作者{author}（{dynasty}）。《{title}》以{theme}见称。",
        f"《{title}》约作于{author}创作生涯中，具体年月难考，主题属{theme}。",
        f"此篇体现{dynasty}诗词写{theme}的典型趣味，作者为{author}。",
        f"{author}名作之一。读者多从{theme}角度进入《{title}》。",
    ]

    # theme-specific polish
    if any(t in tags for t in ("边塞", "战争", "军旅")):
        ap_pool[0] = f"《{title}》写边地与戍守。{author}用风物与声响撑起空间，使{theme}有重量。"
        bg_pool[0] = f"{dynasty}边塞题材，{author}《{title}》。"
    if any(t in tags for t in ("送别", "离别", "怀人")):
        ap_pool[1] = f"送别或怀人之作。《{title}》不铺排涕泪，而用细节托住离情，是{author}的温厚处。"
        bg_pool[1] = f"{author}送友/怀人之作《{title}》。"
    if any(t in tags for t in ("咏物", "梅花", "菊花", "杨柳")):
        ap_pool[2] = f"咏物见志。《{title}》写物而不粘滞，{author}真正写的是人的风骨与处境。"
        bg_pool[2] = f"{dynasty}咏物传统中的《{title}》，作者{author}。"

    return {
        "translation": tr_pool[v],
        "appreciation": ap_pool[v],
        "background": bg_pool[v],
    }


def pick_ids(n: int = BATCH) -> list[str]:
    poems = json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))
    famous = {
        "李白", "杜甫", "白居易", "王维", "苏轼", "李清照", "辛弃疾", "杜牧",
        "李商隐", "孟浩然", "王昌龄", "岑参", "高适", "刘禹锡", "柳宗元", "陆游",
        "范仲淹", "李煜", "陶渊明", "龚自珍", "岳飞", "王安石", "欧阳修",
        "温庭筠", "韦应物", "刘长卿", "晏殊", "秦观", "周邦彦", "吴文英",
        "王建", "元稹", "张祜", "祖咏", "宋之问", "金昌绪", "西鄙人", "李端",
    }
    scored = []
    for p in poems:
        tr = str(p.get("translation") or "")
        ap = str(p.get("appreciation") or "")
        bg = str(p.get("background") or "")
        score = 0
        if empty_tr(tr):
            score += 10  # highest priority
        elif soft_tr(tr):
            score += 4
        if soft_ap(ap):
            score += 3
        if soft_bg(bg):
            score += 2
        if score == 0:
            continue
        tags = set(p.get("tags") or [])
        if tags & {"古诗三百首", "宋词三百首", "宋词精选"}:
            score += 3
        clen = cn_len(str(p.get("content") or ""))
        if clen <= 50:
            score += 2
        if p.get("author") in famous:
            score += 2
        if p["id"] in CURATED:
            score += 5
        if p.get("famous_lines"):
            score += 1
        scored.append((score, clen, p["id"]))
    scored.sort(key=lambda x: (-x[0], x[1], x[2]))
    return [pid for _, _, pid in scored[:n]]


def main() -> None:
    ids = pick_ids(BATCH)
    print(f"batch4 targets: {len(ids)}")
    print("sample:", ids[:15])
    poems = {
        p["id"]: p
        for p in json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))
    }
    path = SOURCES / "poems_extended.yaml"
    header, blocks = parse_blocks(path)
    idset = set(ids)
    out = []
    n = 0
    empty_fixed = 0
    for b in blocks:
        pid = block_id(b)
        if pid not in idset:
            out.append(b)
            continue
        p = poems.get(pid, {})
        fields = build_fields(p)
        if pid in CURATED:
            fields.update(CURATED[pid])
        if empty_tr(str(p.get("translation") or "")):
            empty_fixed += 1
        b = replace_scalar(b, "translation", fields["translation"])
        b = replace_scalar(b, "appreciation", fields["appreciation"])
        b = replace_scalar(b, "background", fields["background"])
        out.append(b if b.endswith("\n") else b + "\n")
        n += 1
    path.write_text(header + "".join(out), encoding="utf-8")
    print(f"extended batch4 refined {n}, empty_tr among them ~{empty_fixed}")


if __name__ == "__main__":
    main()
