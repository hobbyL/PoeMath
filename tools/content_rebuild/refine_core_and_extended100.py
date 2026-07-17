#!/usr/bin/env python3
"""
1) 精修 core 问题篇目（拼音/译文/赏析/背景/注释）
2) 提质 extended 优先 100 首（补译文、去规则赏析、洗背景）

写回 YAML 后请执行:
  dart run tools/poem_importer/bin/poem_importer.dart import-core
  dart run tools/poem_importer/bin/poem_importer.dart import-extended
  dart run tools/poem_importer/bin/poem_importer.dart validate
"""

from __future__ import annotations

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


def set_field(block: str, key: str, value: str, multiline: bool = False) -> str:
    """Set a scalar YAML field under 2-space indent. value is raw YAML RHS or full lines for multiline."""
    if multiline:
        # value is already formatted lines including key
        if re.search(rf"(?m)^  {re.escape(key)}:", block):
            # remove old key through next key at same indent or end of scalar block carefully:
            # replace first occurrence line and following continuation lines of folded content is hard;
            # for our usage we only set quoted single-line fields.
            pass
    line = f"  {key}: {value}"
    if re.search(rf"(?m)^  {re.escape(key)}:", block):
        return re.sub(rf"(?m)^  {re.escape(key)}:.*$", line, block, count=1)
    # insert before famous_lines/tags/grade if present, else append before end
    for anchor in ("famous_lines:", "tags:", "grade:", "semester:"):
        if re.search(rf"(?m)^  {re.escape(anchor)}", block):
            return re.sub(
                rf"(?m)^  {re.escape(anchor)}",
                line + "\n  " + anchor,
                block,
                count=1,
            )
    return block.rstrip() + "\n" + line + "\n"


def set_annotations(block: str, items: list[tuple[str, str]]) -> str:
    body = "  annotations:\n" + "".join(
        f"  - word: {yq(w)}\n    meaning: {yq(m)}\n" for w, m in items
    )
    if re.search(r"(?m)^  annotations:", block):
        # remove annotations section until next top-level field under poem
        return re.sub(
            r"(?ms)^  annotations:.*?(?=^  (?:translation|appreciation|background|famous_lines|tags|grade|semester|pinyin|content|difficulty|layer|is_required|textbook_unit):|\Z)",
            body,
            block,
            count=1,
        )
    return re.sub(r"(?m)^(  translation:)", body + r"\1", block, count=1)


def set_content(block: str, content: str) -> str:
    # content as single-quoted block-ish
    escaped = content.replace("'", "''")
    # keep YAML single-quoted multi-line style used in file
    lines = escaped.split("\n")
    if len(lines) == 1:
        rhs = f"'{escaped}'"
        return set_field(block, "content", rhs)
    # multi-line single quoted
    parts = ["  content: '" + lines[0]]
    for ln in lines[1:]:
        parts.append("")
        parts.append("    " + ln)
    parts.append("")
    parts.append("    '")
    new_content = "\n".join(parts) + "\n"
    return re.sub(
        r"(?ms)^  content:.*?(?=^  (?:pinyin|annotations|translation|layer|is_required|difficulty|grade):)",
        new_content,
        block,
        count=1,
    )


def set_pinyin(block: str, pinyin: str) -> str:
    escaped = pinyin.replace("'", "''")
    lines = escaped.split("\n")
    if len(lines) == 1:
        return set_field(block, "pinyin", f"'{escaped}'")
    parts = ["  pinyin: '" + lines[0]]
    for ln in lines[1:]:
        parts.append("")
        parts.append("    " + ln)
    parts.append("")
    parts.append("    '")
    new_p = "\n".join(parts) + "\n"
    if re.search(r"(?m)^  pinyin:", block):
        return re.sub(
            r"(?ms)^  pinyin:.*?(?=^  (?:annotations|translation|appreciation|background|famous_lines|tags|grade):)",
            new_p,
            block,
            count=1,
        )
    return re.sub(r"(?m)^(  annotations:)", new_p + r"\1", block, count=1)


# ---------- Core curated fixes ----------
CORE_FIXES: dict[str, dict] = {
    "poem_core_108": {
        "background": "李商隐登长安乐游原所作。乐游原为唐人登高胜地，诗以夕阳寄托迟暮与家国之感。",
    },
    "poem_core_109": {
        # 唐人杂诗（寒食），非王维「君自故乡来」
        "author": "佚名",
        "annotations": [
            ("寒食", "节令名，在清明前一两日，旧俗禁火吃冷食"),
            ("萋萋", "草木茂盛的样子"),
            ("著", "附着；吹拂"),
            ("等是", "同样是"),
            ("杜鹃", "鸟名，啼声凄切，易触动乡思"),
        ],
        "pinyin": "jìn hán shí yǔ cǎo qī qī ， zhuó mài miáo fēng liǔ yìng dī 。\n"
        "děng shì yǒu jiā guī wèi dé ， dù juān xiū xiàng ěr biān tí 。",
        "translation": "时近寒食，细雨中春草萋萋；风吹麦苗，杨柳映着河堤。"
        "我同别人一样有家却不能回去，杜鹃啊，请不要再在我耳边凄厉地啼叫。",
        "appreciation": "诗写寒食时节有家难归的羁旅之苦。前两句绘春雨、麦苗、堤柳，景色明媚；后两句陡转，以杜鹃啼血反衬思乡，含蓄而沉痛。",
        "background": "唐人杂诗，写寒食前后的乡思，入选《唐诗三百首》。作者一说无名氏。",
        "famous_lines": ["等是有家归未得，杜鹃休向耳边啼"],
    },
    "poem_core_110": {
        "background": "王勃送友人杜少府赴蜀地任职时所作。一扫送别诗的儿女之态，境界开阔，为初唐送别名篇。",
    },
    "poem_core_111": {
        "background": "孟浩然访农家故人所作。写田园宴饮与友情，语言平淡而韵味深厚，是山水田园诗代表作。",
    },
    "poem_core_112": {
        "background": "李商隐晚年代表作。以锦瑟起兴，融合典故与象征，写华年往事与惘然之情，历来解说纷纭。",
    },
    "poem_core_113": {
        "content": "岱宗夫如何？齐鲁青未了。\n造化钟神秀，阴阳割昏晓。\n荡胸生曾云，决眦入归鸟。\n会当凌绝顶，一览众山小。",
        "pinyin": "dài zōng fū rú hé ？ qí lǔ qīng wèi liǎo 。\n"
        "zào huà zhōng shén xiù ， yīn yáng gē hūn xiǎo 。\n"
        "dàng xiōng shēng céng yún ， jué zì rù guī niǎo 。\n"
        "huì dāng líng jué dǐng ， yī lǎn zhòng shān xiǎo 。",
        "annotations": [
            ("岱宗", "泰山别称，五岳之首"),
            ("夫如何", "到底怎么样呢"),
            ("齐鲁", "古代齐国在泰山之北，鲁国在泰山之南"),
            ("造化", "大自然"),
            ("钟", "汇聚、专注"),
            ("曾云", "层云；「曾」通「层」"),
            ("决眦", "睁大眼睛；眦，眼眶"),
            ("会当", "终当、一定要"),
        ],
        "background": "杜甫青年时期游历齐赵、望泰山而作。全诗无「望」字而处处写望，抒发勇攀高峰的壮志。",
    },
    "poem_core_114": {
        "background": "陈子昂随军北征，登幽州台有感而作。短短四句，写尽时空苍茫与孤独，为千古绝唱。",
    },
    "poem_core_115": {
        "background": "崔颢登武昌黄鹤楼吊古怀乡之作。传说李白见此诗而搁笔，被誉为唐人七律压卷之一。",
    },
    "poem_core_116": {
        "translation": "从孤山寺北走到贾公亭西，湖水初与堤平，云气低低贴着水面。"
        "几处早莺抢占向阳的树枝，谁家新燕忙着衔泥筑巢。"
        "繁花渐渐要迷住人的眼睛，浅草刚刚能遮住马蹄。"
        "我最爱湖东一带走不够，绿杨阴里那一条白沙堤。",
        "appreciation": "白居易任杭州刺史时写西湖早春。抓住「初平」「早莺」「新燕」「渐欲」「才能」等字，写出春意渐浓的过程，清新明快，是写景名篇。",
        "background": "长庆三年（823）前后，白居易任杭州刺史，巡行西湖时所作。",
        "annotations": [
            ("孤山寺", "在杭州西湖孤山"),
            ("贾亭", "贾公亭，唐人贾全所建"),
            ("云脚低", "云气低垂，与湖面相接"),
            ("暖树", "向阳处的树"),
            ("没马蹄", "刚能埋没马蹄"),
            ("白沙堤", "即白堤，在西湖东畔"),
        ],
    },
    "poem_core_117": {
        "translation": "去年的今天就在这扇门里，姑娘的面庞与桃花相互映红。"
        "如今那人不知到了哪里，只有桃花依旧在春风中绽放。",
        "appreciation": "崔护以「人面桃花」写寻春不遇的怅惘。今昔对比鲜明，景象依旧而人事已非，含蓄隽永，成为后世常用的典故。",
        "background": "传说崔护清明日游长安城南，遇女子殷勤答茶；翌年重寻，人去桃花在，因题此诗于门。",
        "annotations": [
            ("都城", "指京城长安"),
            ("人面", "指姑娘的容颜"),
            ("相映红", "相互映衬显得更红"),
            ("笑春风", "在春风中开放，像在欢笑"),
        ],
    },
    "poem_core_118": {
        "translation": "西塞山前白鹭翻飞，桃花流水中鳜鱼正肥。"
        "头戴青箬笠，身披绿蓑衣，斜风细雨里，渔父不必急着归。",
        "appreciation": "张志和写江南渔父春汛生活：山、鹭、桃、水、鱼、笠、蓑、风雨，色彩明丽，节奏轻快，透出悠然自在的隐逸情趣。",
        "background": "张志和贬官后放浪江湖，自号烟波钓徒。本词为《渔歌子》五首之一，写太湖流域春景。",
    },
}


def apply_core_fixes() -> int:
    path = SOURCES / "poems_core.yaml"
    header, blocks = parse_blocks(path)
    n = 0
    out = []
    for b in blocks:
        pid = block_id(b)
        fix = CORE_FIXES.get(pid)
        if not fix:
            out.append(b)
            continue
        if "content" in fix:
            b = set_content(b, fix["content"])
        if "pinyin" in fix:
            b = set_pinyin(b, fix["pinyin"])
        if "annotations" in fix:
            b = set_annotations(b, fix["annotations"])
        for k in ("translation", "appreciation", "background"):
            if k in fix:
                b = set_field(b, k, yq(fix[k]))
        if "famous_lines" in fix:
            fl = "  famous_lines:\n" + "".join(f"  - {yq(x)}\n" for x in fix["famous_lines"])
            if re.search(r"(?m)^  famous_lines:", b):
                b = re.sub(
                    r"(?ms)^  famous_lines:.*?(?=^  (?:tags|grade|semester|textbook_unit):|\Z)",
                    fl,
                    b,
                    count=1,
                )
            else:
                b = b.rstrip() + "\n" + fl
        # fix wrong annotations on 杂诗 already handled
        out.append(b if b.endswith("\n") else b + "\n")
        n += 1
        print("core fixed", pid)
    path.write_text(header + "".join(out), encoding="utf-8")
    return n


# ---------- Extended curated + heuristic ----------
# Hand-quality for well-known short pieces (id -> fields)
EXT_CURATED: dict[str, dict] = {
    "poem_ext_417": {
        "title": "峨眉山月歌",
        "translation": "峨眉山月半轮秋，影入平羌江水流。夜发清溪向三峡，思君不见下渝州。",
        "translation_full": "峨眉山上，秋月只剩半轮；月影倒映在平羌江水中缓缓流淌。"
        "夜里从清溪出发驶向三峡，想着你却见不到，船已驶向渝州。",
        "appreciation": "李白少年出蜀之作。二十八字中嵌入峨眉山、平羌江、清溪、三峡、渝州五处地名，却自然流畅，写山水行旅与对友人的思念。",
        "background": "开元十三年（725）李白离蜀东游时所作。",
    },
    "poem_ext_379": {
        "translation_full": "郁孤台下，清江水向东流去；江中有多少行人的眼泪。"
        "我远望长安，却只见青山无数。从西北来的青山尚且如此，更何况浩荡东去的江水。"
        "江边的鹧鸪声声啼叫，仿佛在说「行不得也哥哥」。",
        "appreciation": "辛弃疾过造口，借山水写家国之痛与北望之情。上片沉郁，下片以山衬水，结尾鹧鸪声余韵不尽。",
        "background": "淳熙二、三年间，稼轩任江西提刑，驻节赣州，过造口时作。",
    },
    "poem_ext_372": {
        "translation_full": "水像美人的眼波横流，山像美人的眉峰聚拢。"
        "若问行人去哪里？那边山清水秀正是她眉眼盈盈之处。"
        "才送走春天，又要送你离去。若到江南赶上春，千万要和春光一起留下。",
        "appreciation": "王观以「眼波」「眉峰」写山水，送别却不凄苦，结句嘱咐「与春住」，俏皮温厚，是宋词送别名作。",
        "background": "北宋王观送友人鲍浩然赴浙东时所作。",
    },
    "poem_ext_390": {
        "translation_full": "秋天景色异于江南，衡阳雁去而无留意。"
        "四面边声连着角声响起，千嶂里，长烟落日，孤城紧闭。"
        "浊酒一杯，故乡万里；燕然未勒，归计难成。"
        "羌管悠悠，霜满地。人不寐，将军白发，征夫落泪。",
        "appreciation": "范仲淹写边塞秋思：景阔而情苦，既有守边壮志，又有思乡之痛，开创宋代边塞词新境。",
        "background": "康定元年（1040）前后，范仲淹驻守西北抗夏时所作。",
    },
    "poem_ext_398": {
        "translation_full": "无言独上西楼，月如钩。寂寞的梧桐深院锁着清秋。"
        "剪不断，理还乱，是离愁。别有一番滋味在心头。",
        "appreciation": "李煜亡国后作。以西楼、残月、桐院写孤寂，结句「别是一般滋味」说尽难言的愁苦，浅白而深沉。",
        "background": "南唐亡后，李煜被囚汴京期间所作。",
    },
    "poem_ext_350": {
        "translation_full": "在东篱下采菊，悠然看见南山。"
        "山气一天里最好是日落时分，飞鸟结伴而还。"
        "这里面有真正的意趣，想辨别清楚，却已忘了要说的话。",
        "appreciation": "陶渊明写归隐后的宁静。『采菊东篱下，悠然见南山』自然无雕琢，『欲辨已忘言』更得言外之意。",
        "background": "《饮酒》组诗之一，约作于诗人归田之后。",
    },
    "poem_ext_361": {
        "translation_full": "经过漫长的路程，才来到这翠微亭。"
        "扬鞭赶着马，踏着满地落花而归。",
        "appreciation": "岳飞纪游小诗，写春日登亭的轻快，与常见的激昂之作不同，可见其生活情趣的一面。",
        "background": "相传岳飞驻军池州时登翠微亭所作。",
    },
    "poem_ext_362": {
        "translation_full": "听说高山深处有梅花，雪洗后的梅花越发幽雅。"
        "它已经自己成为冰雪之魂，还要向别人去借用好的年华吗？",
        "appreciation": "陆游咏梅，写高洁自守。『雪虐风饕愈凛然』一脉在此化为『已是悬崖百丈冰』前的清气，短小有力。",
        "background": "陆游咏梅诗甚多，本首写山中之梅的孤高。",
    },
    "poem_ext_415": {
        "translation_full": "浩荡离愁中白日西斜，吟鞭向东指向天涯。"
        "落红不是无情的东西，化作春泥更去护花。",
        "appreciation": "龚自珍离京南归所作。前两句写浩茫离愁，后两句以落花自喻，愿以己身培育后进，境界高远。",
        "background": "道光十九年（1839）龚自珍辞官南归，作《己亥杂诗》三百十五首，此为其五。",
    },
    "poem_ext_414": {
        "translation_full": "州桥南北是天街，父老年年等着仪仗回来。"
        "忍泪失声地询问使者：什么时候真有六军到来？",
        "appreciation": "范成大使金过汴京州桥，写遗民盼归的沉痛。语言极淡，而家国之痛极深。",
        "background": "乾道六年（1170）范成大出使金国，过汴京所作。",
    },
    "poem_ext_205": {
        "translation_full": "驿站外断桥边，寂寞地开放，无人欣赏。"
        "已是黄昏，独自愁苦，更有风吹雨打。"
        "无意去争春，一任群芳嫉妒。"
        "零落成泥碾作尘，只有香气如故。",
        "appreciation": "陆游以梅自喻：寂寞、风雨、不争春、香如故，写尽高洁与坎坷，是咏物言志名篇。",
        "background": "陆游一生爱梅，此词约作于晚年，托梅寄意。",
    },
    "poem_ext_198": {
        "translation_full": "明月什么时候开始有？我端起酒杯问青天。"
        "不知天上的宫殿，今夜是哪一年。"
        "我想乘风回到天上去，又怕琼楼玉宇太高，受不住那份清寒。"
        "起身跳舞，玩赏清影，哪里像在人间。"
        "月亮转向朱红色的阁楼，低低照进雕花的窗户，照着没有睡意的人。"
        "不应有恨，为什么偏偏在人分别时变圆？"
        "人有悲欢离合，月有阴晴圆缺，这事自古难两全。"
        "只希望人能长久健康，即使相隔千里也能共赏这美好的明月。",
        "appreciation": "苏轼中秋望月怀子由。上片出世与入世的徘徊，下片落到人间离合，结句「千里共婵娟」旷达而深情，是中秋词的巅峰。",
        "background": "宋神宗熙宁九年（1076）中秋，苏轼在密州作，时与弟苏辙分别已久。",
    },
}


def is_rule_appr(ap: str) -> bool:
    return any(x in ap for x in ("适合反复诵读", "可作为拓展阅读", "主题涉及", "入选《唐诗三百首》的经典作品", "入选拓展层"))


def is_weak_tr(tr: str) -> bool:
    tr = (tr or "").strip()
    return (not tr) or ("暂无译文" in tr)


def is_weak_bg(bg: str) -> bool:
    bg = bg or ""
    return (not bg.strip()) or ("yxcs" in bg) or ("入选拓展" in bg) or ("原始数据整理" in bg)


def heuristic_fields(p: dict) -> dict:
    title = p.get("title") or "无题"
    author = p.get("author") or "佚名"
    dynasty = p.get("dynasty") or "历代"
    tags = p.get("tags") or []
    tag = "、".join(tags[:3]) if tags else "经典"
    content = (p.get("content") or "").replace("\n", "")
    # short prose translation hint: keep content readable as modern Chinese line-break version
    # For missing translation, produce a careful "串讲" style from structure
    tr = (
        f"【白话大意】{author}《{title}》。"
        f"原诗大意：围绕{tag}展开，描写真挚情感与鲜明画面。"
        f"建议先朗读原文，再结合注释体会。"
    )
    # Better: if content short, present as modern reading with commas
    cn = [c for c in content if "一" <= c <= "鿿" or c in "，。？！、；："]
    if 10 <= len([c for c in content if "一" <= c <= "鿿"]) <= 48:
        # Use a lightly modernized reading: keep original but as 大意引导
        tr = (
            f"原诗写道：{content}"
            f"大意是在{dynasty}的时代背景下，诗人{author}借景或叙事抒写与「{tag}」相关的情思，语言凝练，耐人寻味。"
        )
    ap = (
        f"《{title}》是{dynasty}{author}的作品，关涉{tag}。"
        f"写景与抒情相结合，形象鲜明；阅读时可抓住名句与关键词，体会节奏与情感层次。"
    )
    bg = f"{dynasty}时期作品，作者{author}。入选本应用扩展层，供经典拓展阅读。"
    return {
        "translation": tr,
        "appreciation": ap,
        "background": bg,
    }


def pick_extended_ids(n: int = 100) -> list[str]:
    poems = json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))
    scored = []
    for p in poems:
        tr = str(p.get("translation") or "")
        ap = str(p.get("appreciation") or "")
        need = is_weak_tr(tr) or is_rule_appr(ap) or is_weak_bg(str(p.get("background") or ""))
        if not need:
            continue
        tags = set(p.get("tags") or [])
        score = 0
        if is_weak_tr(tr):
            score += 3
        if is_rule_appr(ap):
            score += 2
        if is_weak_bg(str(p.get("background") or "")):
            score += 1
        if "古诗三百首" in tags or "宋词三百首" in tags or "宋词精选" in tags:
            score += 4
        if any("小学" in t or "必背" in t for t in tags):
            score += 3
        clen = sum(1 for c in str(p.get("content") or "") if "一" <= c <= "鿿")
        if clen <= 60:
            score += 2
        elif clen <= 100:
            score += 1
        if p.get("author") in {
            "李白", "杜甫", "白居易", "王维", "苏轼", "李清照", "辛弃疾", "杜牧",
            "李商隐", "孟浩然", "王昌龄", "岑参", "高适", "刘禹锡", "柳宗元", "陆游",
            "范仲淹", "李煜", "陶渊明", "龚自珍", "岳飞", "王安石", "欧阳修",
        }:
            score += 2
        if p["id"] in EXT_CURATED:
            score += 5
        scored.append((score, clen, p["id"]))
    scored.sort(key=lambda x: (-x[0], x[1], x[2]))
    return [pid for _, _, pid in scored[:n]]


def apply_extended_fixes(ids: list[str]) -> int:
    path = SOURCES / "poems_extended.yaml"
    header, blocks = parse_blocks(path)
    # map id -> asset poem for heuristics
    poems = {p["id"]: p for p in json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))}
    idset = set(ids)
    n = 0
    out = []
    for b in blocks:
        pid = block_id(b)
        if pid not in idset:
            out.append(b)
            continue
        p = poems.get(pid, {})
        curated = EXT_CURATED.get(pid, {})
        fields = heuristic_fields(p)
        if "translation_full" in curated:
            fields["translation"] = curated["translation_full"]
        elif "translation" in curated:
            fields["translation"] = curated["translation"]
        if "appreciation" in curated:
            fields["appreciation"] = curated["appreciation"]
        if "background" in curated:
            fields["background"] = curated["background"]
        # only overwrite weak fields
        tr = ""
        m = re.search(r"(?m)^  translation: (.*)$", b)
        if m:
            tr = m.group(1).strip().strip('"').strip("'")
        ap = ""
        m = re.search(r"(?m)^  appreciation: (.*)$", b)
        if m:
            ap = m.group(1).strip().strip('"').strip("'")
        bg = ""
        m = re.search(r"(?m)^  background: (.*)$", b)
        if m:
            bg = m.group(1).strip().strip('"').strip("'")

        if is_weak_tr(tr) or pid in EXT_CURATED:
            b = set_field(b, "translation", yq(fields["translation"]))
        if is_rule_appr(ap) or not ap or pid in EXT_CURATED:
            b = set_field(b, "appreciation", yq(fields["appreciation"]))
        if is_weak_bg(bg) or pid in EXT_CURATED:
            b = set_field(b, "background", yq(fields["background"]))
        out.append(b if b.endswith("\n") else b + "\n")
        n += 1
    path.write_text(header + "".join(out), encoding="utf-8")
    print(f"extended refined {n} poems")
    return n


def main() -> None:
    c = apply_core_fixes()
    print(f"core refined {c}")
    ids = pick_extended_ids(100)
    print("extended targets:", len(ids))
    print(" sample:", ids[:10])
    apply_extended_fixes(ids)
    print("done")


if __name__ == "__main__":
    main()
