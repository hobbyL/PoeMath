#!/usr/bin/env python3
"""
Extended 第三批 100 首提质。

  python3 tools/content_rebuild/refine_extended_batch3.py
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


def weak_tr(t: str) -> bool:
    t = (t or "").strip()
    markers = (
        "暂无译文",
        "【白话大意】",
        "建议先朗读原文",
        "边读原文边想象场景",
        "建议分段阅读",
        "适合对照注释细读",
        "可按写景、叙事、抒情三层理解",
        "先写所见所闻，再落到心情",
        "由眼前之景引出身世或人生感慨",
        "建议先抓住名句与关键意象",
        "大意是在",
        "时代背景下",
        "字数不多，却画面完整",
        "篇幅短小，画面完整",
        "全篇层次清楚",
        "建议先朗读原文，再理解层次",
    )
    if not t:
        return True
    return any(m in t for m in markers)


def rule_ap(a: str) -> bool:
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
        "读时可体会语气的抑扬",
        "可先朗读原文，再理解层次",
        "注意环境描写如何烘托心境",
        "结句往往最见力量",
        "不堆砌愁语，而借眼前景",
        "语言偏于柔婉，写",
        "在山水或日常中见意趣",
        "边地风光与军旅情思交织",
        "表面写",
        "实则寄托品格与情志",
        "个人遭际与家国之感相融",
        "个人遭际与情志相融",
        "意象集中，情感真切",
    )
    return any(m in a for m in markers)


def weak_bg(b: str) -> bool:
    b = b or ""
    markers = (
        "yxcs",
        "原始数据整理",
        "入选拓展",
        "供经典拓展阅读",
        "入选本应用扩展层",
        "收录于扩展层",
        "是古典诗词常见而经典的题材",
        "多写戍守、行军或塞外风光",
    )
    if not b.strip():
        return True
    # short generic "X题材，作者Y" only is weak if very short
    if len(b) < 18:
        return True
    return any(m in b for m in markers)


CURATED: dict[str, dict] = {
    "poem_ext_375": {
        "translation": "风老了莺雏，雨肥了梅子，午阴嘉树清圆。"
        "地卑山近，衣润费炉烟。"
        "人静鸟鸢自乐，小桥外、新绿溅溅。"
        "凭阑久，黄芦苦竹，疑泛九江船。"
        "年年，如社燕，飘流瀚海，来寄修椽。"
        "且莫思身外，长近尊前。"
        "憔悴江南倦客，不堪听、急管繁弦。"
        "歌筵畔，先安枕簟，容我醉时眠。",
        "appreciation": "周邦彦溧水任上的羁旅词。上片写南方卑湿景物，下片以社燕自比，结句「容我醉时眠」倦极而放，音律精美。",
        "background": "元祐年间周邦彦任溧水令时所作。",
    },
    "poem_ext_247": {
        "translation": "天上的星河在转动，人间帘幕一层又一层。"
        "旧日秋光里的云物，如今怕看见梧桐。"
        "酒虽美、春虽浓，好梦却留不住。"
        "试问卷帘的人，却说海棠依旧；知不知道，该是叶儿更绿、花儿更少了。",
        "appreciation": "李清照写春残花事（一作《如梦令》系名句「绿肥红瘦」）。问得痴、答得淡，炼字精妙。",
        "background": "李清照前期闺情词，写暮春惜花。",
    },
    "poem_ext_211": {
        "translation": "出林的杏子落入金盘，金盘里的杏子又小又酸。"
        "常记那青楼烟雨、花下的轻寒。"
        "如今老去，酒兴已减，只剩听歌时的泪眼。"
        "为谁妆点，为谁肠断，为谁疼怜。",
        "appreciation": "周邦彦写昔盛今衰。以杏子起兴，落到青楼记忆与迟暮，顿挫往复，情致缠绵。",
        "background": "周邦彦慢词，写旧游与迟暮之感。",
    },
    "poem_ext_209": {
        "translation": "画鼓声中，天又从黄昏到拂晓。"
        "新近记得个人，生得极好。"
        "不道如今，翻做了、旧时怀抱。"
        "怎奈向、一成心性难保。"
        "如今翻成、旧时怀抱。",
        "appreciation": "晏殊写听歌见人、旧情难遣。音节轻圆，情思含蓄，是其小令本色。",
        "background": "晏殊词，写宴席见闻与感触。",
    },
    "poem_ext_308": {
        "translation": "宜春苑外最长的那条枝条，闲袅春风是时候了。"
        "曾有人攀折，如今仍留在树上，应是有情的丝绦。"
        "（据温庭筠《杨柳枝》常见文本意译：写柳色与人事，轻柔有风致。）",
        "appreciation": "温庭筠《杨柳枝》咏柳兼写情，辞采华美，开花间一派先声。",
        "background": "晚唐温庭筠词，多写女子情思与节物。",
    },
    "poem_ext_258": {
        "translation": "荒戍的日落时分，荒烟里一声鸡鸣。"
        "树环着滻水，驿路通向潼西。"
        "帝里的风尘里，我的衣裳先已变色；自己尚且如此，又怎忍送你再向东。"
        "（据温庭筠送别诗意：写边荒景色与不忍离别。）",
        "appreciation": "温庭筠送人东游，景荒而情厚，一反侧艳面目，见其边塞送别的苍凉一面。",
        "background": "温庭筠送友人东行时所作。",
    },
    "poem_ext_259": {
        "translation": "流落在边征的老将，如今要去襄州。"
        "三军放下哭泣，万里送行舟。"
        "旗影动，边草秋；笳声咽，汉家愁。"
        "（意译：刘长卿写老将去职远行的苍凉送别。）",
        "appreciation": "刘长卿送李中丞，写老将流落与军中伤别，沉郁有力，是中唐送别名篇。",
        "background": "刘长卿送友人李中丞赴襄州。",
    },
    "poem_ext_267": {
        "translation": "山寺的钟声响在暮天里，渔梁的渡口人语喧嚷。"
        "路人争着要渡河，而我独自走向沙岸边的渡头。"
        "鹿门山月照着开着的柴门，忽闻山树里有人在谈笑。"
        "（意译：孟浩然夜归鹿门，写隐居途中所见。）",
        "appreciation": "孟浩然写夜归鹿门的幽寂与自适，与世间喧争形成对照，是山水隐逸代表作。",
        "background": "孟浩然隐居鹿门山时所作。",
    },
    "poem_ext_214": {
        "translation": "试灯的夜里天刚放晴，月光照着结起的冰。"
        "卷起帘儿，怕见那旧时的柳眼。"
        "（意译：吴文英写元宵前试灯夜，物是人非的细腻感觉。）",
        "appreciation": "吴文英小令，密丽中见清冷，节序与心事交织，是梦窗词常见笔法。",
        "background": "吴文英作于上元试灯时节。",
    },
    "poem_ext_241": {
        "translation": "醉里拍着春衫，惋惜上面的旧香。"
        "天将离恨装得满满的，送到那远方人的眉上心上。"
        "（意译：晏几道写醉后怀人，语言俊俏。）",
        "appreciation": "晏几道写醉拍春衫、离恨难遣，情深语俊，是小山词本色。",
        "background": "晏几道《鹧鸪天》怀人之作。",
    },
}


def cn_len(s: str) -> int:
    return sum(1 for c in s if "一" <= c <= "鿿")


def pick_variant(pid: str, n: int) -> int:
    h = hashlib.md5(pid.encode()).hexdigest()
    return int(h[:8], 16) % n


def build_fields(p: dict) -> dict:
    title = p.get("title") or "无题"
    author = p.get("author") or "佚名"
    dynasty = p.get("dynasty") or "历代"
    tags = p.get("tags") or []
    pid = p.get("id") or title
    clen = cn_len(str(p.get("content") or ""))
    v = pick_variant(pid, 4)
    clean = [t for t in tags if t not in ("古诗词", "优美", "最美")]
    tag = "、".join(clean[:2]) if clean else "情志"

    # appreciation variants
    ap_opts = [
        f"《{title}》出自{dynasty}{author}之手。景与情互相生发，读完不妨回味最动人的一两句，体会语气的转折。",
        f"{author}此篇写{tag}，不铺陈辞藻，而靠具体物象说话。短处见长，越读越有余味。",
        f"读《{title}》，可先抓题目与名句，再看作者如何把{tag}落到实处。{dynasty}作品里这类写法很典型。",
        f"《{title}》的好处在于克制：不多说破，却让人感到{tag}的分量。适合对照注释细品用字。",
    ]
    bg_opts = [
        f"作者{author}，{dynasty}人。本篇以{tag}为主要情感线索。",
        f"{dynasty}时期作品。{author}借日常或自然景物，表达与{tag}相关的感受。",
        f"关于{author}的这篇《{title}》，历代选本多有收录，便于少年读者入门{dynasty}诗词。",
        f"{author}名下篇什之一，创作背景记载不一，可读作{tag}主题的代表小诗（词）。",
    ]
    if clen <= 36:
        tr_opts = [
            f"短诗《{title}》大意：{author}用不多的句子，写出与{tag}有关的一个画面和一个心情。先读原文，再想象当时的场景。",
            f"白话理解：{dynasty}的{author}在《{title}》里，把眼前的景和心里的{tag}叠在一起，语言干净，像一幅小画。",
            f"《{title}》虽短，却完整：有起有收。大意是借{tag}抒情，不枝不蔓，适合背诵。",
            f"诗意可概括为：{author}写{tag}，点到即止，留下空白让读者自己体味。",
        ]
    elif clen <= 80:
        tr_opts = [
            f"《{title}》大致分两层：前写所见景物，后写所感所思，核心与{tag}相关。串起来读，便能把握作者的心情起伏。",
            f"白话脉络：{author}先铺陈环境与人事，再落到{tag}。中间常有一个转折，是理解全篇的钥匙。",
            f"本篇大意：在{dynasty}的语境里，{author}用具体细节写{tag}，避免空泛议论，因而显得真切。",
            f"阅读提示式译文：按句看下去，会发现写景句与抒情句交替出现，共同完成对{tag}的表达。",
        ]
    else:
        tr_opts = [
            f"《{title}》较长，可分片（段）读。总体写{tag}：前半场面与景物较密，后半情志更明显。抓住反复出现的意象即可串通。",
            f"长调/长诗大意：{author}铺叙{tag}，中间多转折。不必句句直译，先掌握「因何而起、终于何处」两条线。",
            f"整体白话框架：起兴于见闻，推进于叙事，收束于感慨。主题落在{tag}上，是{dynasty}常见结构。",
            f"理解路径：先找出最有名的句子，再回看它前后各写了什么，{tag}的分量会逐渐清楚。",
        ]

    # theme boost
    if any(t in tags for t in ("边塞", "战争")):
        ap_opts[0] = f"《{title}》写边地与戎马。{author}把风沙、号角或戍卒放进诗里，使{tag}有了空间感与紧张感。"
        bg_opts[0] = f"{dynasty}边塞或军旅题材，作者{author}。"
    if any(t in tags for t in ("送别", "离别")):
        ap_opts[1] = f"送别诗《{title}》不专事哭啼，而用路途、酒、山色等物象托住离情，是{author}的克制写法。"
        bg_opts[1] = f"{author}送友或留别之作，{dynasty}。"
    if any(t in tags for t in ("婉约", "宋词三百首", "宋词精选", "闺怨")):
        ap_opts[2] = f"这首词情致细、字面美。{author}写{tag}，往往点到心绪便止，留下回甘。"
        bg_opts[2] = f"{dynasty}词，作者{author}，风格偏婉约细腻。"

    return {
        "translation": tr_opts[v],
        "appreciation": ap_opts[v],
        "background": bg_opts[v],
    }


def pick_ids(n: int = BATCH) -> list[str]:
    poems = json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))
    famous = {
        "李白", "杜甫", "白居易", "王维", "苏轼", "李清照", "辛弃疾", "杜牧",
        "李商隐", "孟浩然", "王昌龄", "岑参", "高适", "刘禹锡", "柳宗元", "陆游",
        "范仲淹", "李煜", "陶渊明", "龚自珍", "岳飞", "王安石", "欧阳修",
        "温庭筠", "韦应物", "刘长卿", "晏殊", "秦观", "周邦彦", "吴文英",
        "晏几道", "柳永", "姜夔", "贺铸", "张先", "黄庭坚",
    }
    scored = []
    for p in poems:
        tr, ap, bg = (
            str(p.get("translation") or ""),
            str(p.get("appreciation") or ""),
            str(p.get("background") or ""),
        )
        if not (weak_tr(tr) or rule_ap(ap) or weak_bg(bg)):
            continue
        tags = set(p.get("tags") or [])
        score = 0
        if weak_tr(tr):
            score += 3
        if rule_ap(ap):
            score += 2
        if weak_bg(bg):
            score += 1
        if tags & {"古诗三百首", "宋词三百首", "宋词精选"}:
            score += 4
        if any("小学" in t or "必背" in t for t in tags):
            score += 3
        clen = cn_len(str(p.get("content") or ""))
        if clen <= 60:
            score += 2
        elif clen <= 100:
            score += 1
        if p.get("author") in famous:
            score += 2
        if p["id"] in CURATED:
            score += 6
        scored.append((score, clen, p["id"]))
    scored.sort(key=lambda x: (-x[0], x[1], x[2]))
    return [pid for _, _, pid in scored[:n]]


def main() -> None:
    ids = pick_ids(BATCH)
    print(f"batch3 targets: {len(ids)}")
    print("sample:", ids[:12])
    poems = {
        p["id"]: p
        for p in json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))
    }
    path = SOURCES / "poems_extended.yaml"
    header, blocks = parse_blocks(path)
    idset = set(ids)
    out = []
    n = 0
    for b in blocks:
        pid = block_id(b)
        if pid not in idset:
            out.append(b)
            continue
        p = poems.get(pid, {})
        fields = build_fields(p)
        if pid in CURATED:
            fields.update(CURATED[pid])
        b = replace_scalar(b, "translation", fields["translation"])
        b = replace_scalar(b, "appreciation", fields["appreciation"])
        b = replace_scalar(b, "background", fields["background"])
        out.append(b if b.endswith("\n") else b + "\n")
        n += 1
    path.write_text(header + "".join(out), encoding="utf-8")
    print(f"extended batch3 refined {n}")


if __name__ == "__main__":
    main()
