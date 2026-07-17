#!/usr/bin/env python3
"""
扩展层扩量 + 作者覆盖提升（开发期，无迁移包袱）。

策略：
1. 从 explore 中挑选偏经典篇目提升为 extended（优先 唐诗/宋词三百首、
   小学相关标签、唐宋短篇），目标 extended ≈ 400。
2. 为诗量 ≥2 的缺失作者补 seed（含一批精选 brief + 通用简介兜底）。
3. 写回 YAML 后由 poem_importer 重新生成 JSON。

用法（项目根）:
  python3 tools/content_rebuild/expand_extended_authors.py
  dart run tools/poem_importer/bin/poem_importer.dart import-all
  dart run tools/poem_importer/bin/poem_importer.dart validate
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "tools" / "poem_importer" / "data" / "sources"
ASSETS = ROOT / "assets" / "data"

TARGET_EXTENDED = 400
MIN_AUTHOR_POEMS = 2

# Extra curated authors (name -> meta)
EXTRA_AUTHORS: dict[str, dict] = {
    "张炎": {"dynasty": "宋", "life_years": "1248-约1320", "title": "玉田", "brief": "南宋末词人，词风清空骚雅，精于音律，著有《词源》。"},
    "林逋": {"dynasty": "宋", "life_years": "967-1028", "title": "和靖先生", "brief": "北宋隐逸诗人，爱梅养鹤，称「梅妻鹤子」。诗风淡远，《山园小梅》最为著名。"},
    "王国维": {"dynasty": "近现代", "life_years": "1877-1927", "title": "", "brief": "近代学者、词人。治学贯通中西，词作与词论《人间词话》影响深远。"},
    "史达祖": {"dynasty": "宋", "life_years": "约1163-约1220", "title": "", "brief": "南宋词人，善咏物，词风细腻工巧。"},
    "司马光": {"dynasty": "宋", "life_years": "1019-1086", "title": "", "brief": "北宋史学家、政治家，主编《资治通鉴》。诗文亦有可观之作。"},
    "刘义庆": {"dynasty": "南朝宋", "life_years": "403-444", "title": "", "brief": "南朝文学家，编撰《世说新语》，记魏晋名士言行，影响极大。"},
    "范成大": {"dynasty": "宋", "life_years": "1126-1193", "title": "石湖", "brief": "南宋诗人，田园诗成就突出，与杨万里、陆游、尤袤并称中兴四大诗人。"},
    "韩翃": {"dynasty": "唐", "life_years": "生卒年不详", "title": "大历十才子", "brief": "中唐诗人，大历十才子之一。《寒食》一诗广为流传。"},
    "崔护": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，以《题都城南庄》「人面桃花」一典闻名。"},
    "赵师秀": {"dynasty": "宋", "life_years": "1170-1219", "title": "永嘉四灵", "brief": "南宋诗人，永嘉四灵之一，诗风清苦工巧。"},
    "宋之问": {"dynasty": "唐", "life_years": "约656-约712", "title": "", "brief": "初唐诗人，与沈佺期并称，近体律诗定型过程中的重要人物。"},
    "祖咏": {"dynasty": "唐", "life_years": "约699-约746", "title": "", "brief": "盛唐诗人，山水诗清新，《终南望余雪》尤为著名。"},
    "朱庆馀": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "中唐诗人，《近试上张水部》以比兴写科举心态，流传甚广。"},
    "刘方平": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，写景诗细腻，《月夜》等小诗清新可诵。"},
    "马戴": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "晚唐诗人，边塞与写景诗清峭，为晚唐五律名家。"},
    "崔涂": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，羁旅诗情感真挚，《除夜有怀》等较有名。"},
    "朱敦儒": {"dynasty": "宋", "life_years": "1081-1159", "title": "岩壑", "brief": "两宋之交词人，早年豪放，南渡后多写隐逸闲适。"},
    "张元干": {"dynasty": "宋", "life_years": "1091-约1161", "title": "", "brief": "南宋词人，词多爱国感慨，风格豪迈。"},
    "韩偓": {"dynasty": "唐", "life_years": "约842-约923", "title": "", "brief": "晚唐诗人，诗风绮丽，亦有感时伤乱之作。"},
    "张乔": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，写景抒情清雅。"},
    "王涯": {"dynasty": "唐", "life_years": "约764-835", "title": "", "brief": "中唐诗人、政治家，诗作以宫词等见长。"},
    "陆龟蒙": {"dynasty": "唐", "life_years": "约？-约881", "title": "", "brief": "晚唐文学家，与皮日休齐名，诗文多写隐逸与咏物。"},
    "朱栴": {"dynasty": "明", "life_years": "生卒年不详", "title": "", "brief": "明代宗室文人，有诗文传世。"},
    "向子諲": {"dynasty": "宋", "life_years": "1085-1152", "title": "", "brief": "南宋词人，词分江南、江北，风格清旷。"},
    "陈克": {"dynasty": "宋", "life_years": "1081-1137", "title": "", "brief": "南北宋之交词人，词风清丽。"},
    "王禹偁": {"dynasty": "宋", "life_years": "954-1001", "title": "", "brief": "北宋文学家，诗文通俗，关心民谟，开北宋诗文革新先声。"},
    "王观": {"dynasty": "宋", "life_years": "生卒年不详", "title": "", "brief": "北宋词人，《卜算子·送鲍浩然之浙东》以「水是眼波横」著名。"},
    "王雱": {"dynasty": "宋", "life_years": "1044-1076", "title": "", "brief": "北宋文学家，王安石之子，词作清丽。"},
    "牛峤": {"dynasty": "五代", "life_years": "生卒年不详", "title": "", "brief": "前蜀词人，花间词派作者，词多写艳情与闺怨。"},
    "皇甫松": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐词人，花间词作者，小令清丽。"},
    "张抡": {"dynasty": "宋", "life_years": "生卒年不详", "title": "", "brief": "南宋词人，词多写景与节令。"},
    "俞国宝": {"dynasty": "宋", "life_years": "生卒年不详", "title": "", "brief": "南宋词人，《风入松》咏西湖春景流传较广。"},
    "蒋氏女": {"dynasty": "宋", "life_years": "生卒年不详", "title": "", "brief": "南宋女词人，存词虽少，《减字木兰花·题雄州驿》情真感人。"},
    "汪藻": {"dynasty": "宋", "life_years": "1079-1154", "title": "", "brief": "南宋文学家，诗文俱佳。"},
    "曾巩": {"dynasty": "宋", "life_years": "1019-1083", "title": "南丰先生", "brief": "北宋散文家，唐宋八大家之一，文风古雅平正。"},
    "沈佺期": {"dynasty": "唐", "life_years": "约656-约715", "title": "", "brief": "初唐诗人，与宋之问并称，近体诗格律成熟的代表人物。"},
    "贺知章": {"dynasty": "唐", "life_years": "659-744", "title": "四明狂客", "brief": "唐代诗人、书法家，诗风清新，《咏柳》《回乡偶书》家喻户晓。"},
    "刘昚虚": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "盛唐诗人，山水田园诗清淡幽远。"},
    "綦毋潜": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，多写方外与山水。"},
    "丘为": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，田园诗风格淡泊。"},
    "裴迪": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，与王维唱和，山水诗清幽。"},
    "元结": {"dynasty": "唐", "life_years": "719-772", "title": "", "brief": "中唐文学家，诗风质朴，关注现实。"},
    "顾况": {"dynasty": "唐", "life_years": "约727-约815", "title": "", "brief": "中唐诗人，乐府诗有新意，影响白居易等。"},
    "戎昱": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "中唐诗人，边塞与感时诗较有特色。"},
    "戴叔伦": {"dynasty": "唐", "life_years": "约732-约789", "title": "", "brief": "中唐诗人，诗风清新，写景与羁旅皆有佳作。"},
    "李端": {"dynasty": "唐", "life_years": "生卒年不详", "title": "大历十才子", "brief": "中唐诗人，大历十才子之一。"},
    "耿湋": {"dynasty": "唐", "life_years": "生卒年不详", "title": "大历十才子", "brief": "中唐诗人，大历十才子之一。"},
    "韩偓": {"dynasty": "唐", "life_years": "约842-约923", "title": "", "brief": "晚唐诗人。"},
    "罗隐": {"dynasty": "唐", "life_years": "833-909", "title": "", "brief": "晚唐文学家，咏史与讽刺小品尖锐。"},
    "杜牧": {"dynasty": "唐", "life_years": "803-约852", "title": "小杜", "brief": "晚唐诗人，诗风俊爽。"},
    "皮日休": {"dynasty": "唐", "life_years": "约838-约883", "title": "", "brief": "晚唐文学家，与陆龟蒙齐名。"},
    "聂夷中": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，诗多写民生疾苦。"},
    "秦韬玉": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐诗人，《贫女》一诗广为人知。"},
    "张泌": {"dynasty": "唐", "life_years": "生卒年不详", "title": "", "brief": "唐五代诗人、词人。"},
    "和凝": {"dynasty": "五代", "life_years": "898-955", "title": "", "brief": "五代词人，花间词作者。"},
    "欧阳炯": {"dynasty": "五代", "life_years": "896-971", "title": "", "brief": "五代词人，花间词派重要作者。"},
    "顾敻": {"dynasty": "五代", "life_years": "生卒年不详", "title": "", "brief": "五代词人，花间词作者。"},
    "孙光宪": {"dynasty": "五代", "life_years": "约900-968", "title": "", "brief": "五代词人。"},
    "冯延巳": {"dynasty": "五代", "life_years": "约903-960", "title": "", "brief": "南唐词人。"},
    "李璟": {"dynasty": "五代", "life_years": "916-961", "title": "南唐中主", "brief": "南唐中主，词作感伤清丽，影响李煜。"},
    "范仲淹": {"dynasty": "宋", "life_years": "989-1052", "title": "", "brief": "北宋名臣、文学家。"},
    "张先": {"dynasty": "宋", "life_years": "990-1078", "title": "张三影", "brief": "北宋词人。"},
    "晏殊": {"dynasty": "宋", "life_years": "991-1055", "title": "晏元献", "brief": "北宋词人。"},
    "宋祁": {"dynasty": "宋", "life_years": "998-1061", "title": "", "brief": "北宋文学家，「红杏尚书」之称源于名句。"},
    "梅尧臣": {"dynasty": "宋", "life_years": "1002-1060", "title": "", "brief": "北宋诗人，诗风平淡，推动宋诗发展。"},
    "欧阳修": {"dynasty": "宋", "life_years": "1007-1072", "title": "醉翁", "brief": "北宋文坛领袖。"},
    "苏舜钦": {"dynasty": "宋", "life_years": "1008-1048", "title": "", "brief": "北宋诗人，诗风豪健。"},
    "柳永": {"dynasty": "宋", "life_years": "约984-约1053", "title": "柳七", "brief": "北宋词人，慢词大家。"},
    "王安石": {"dynasty": "宋", "life_years": "1021-1086", "title": "半山", "brief": "北宋政治家、文学家，唐宋八大家之一。"},
    "苏轼": {"dynasty": "宋", "life_years": "1037-1101", "title": "东坡", "brief": "北宋文学家，诗书画词文皆精。"},
    "黄庭坚": {"dynasty": "宋", "life_years": "1045-1105", "title": "山谷", "brief": "北宋诗人，江西诗派宗主。"},
    "秦观": {"dynasty": "宋", "life_years": "1049-1100", "title": "淮海", "brief": "北宋词人。"},
    "贺铸": {"dynasty": "宋", "life_years": "1052-1125", "title": "", "brief": "北宋词人。"},
    "周邦彦": {"dynasty": "宋", "life_years": "1056-1121", "title": "清真", "brief": "北宋词人。"},
    "李清照": {"dynasty": "宋", "life_years": "1084-约1155", "title": "易安", "brief": "宋代女词人。"},
    "陆游": {"dynasty": "宋", "life_years": "1125-1210", "title": "放翁", "brief": "南宋诗人，创作极丰，爱国诗篇感人。"},
    "范成大": {"dynasty": "宋", "life_years": "1126-1193", "title": "石湖", "brief": "南宋诗人。"},
    "杨万里": {"dynasty": "宋", "life_years": "1127-1206", "title": "诚斋", "brief": "南宋诗人，诚斋体活泼自然。"},
    "朱熹": {"dynasty": "宋", "life_years": "1130-1200", "title": "", "brief": "南宋理学家、教育家，亦有诗作。"},
    "辛弃疾": {"dynasty": "宋", "life_years": "1140-1207", "title": "稼轩", "brief": "南宋词人。"},
    "姜夔": {"dynasty": "宋", "life_years": "约1155-约1221", "title": "白石", "brief": "南宋词人、音乐家。"},
    "吴文英": {"dynasty": "宋", "life_years": "约1200-约1260", "title": "梦窗", "brief": "南宋词人。"},
    "文天祥": {"dynasty": "宋", "life_years": "1236-1283", "title": "文山", "brief": "南宋末大臣、文学家。"},
    "元好问": {"dynasty": "金", "life_years": "1190-1257", "title": "", "brief": "金元之际文学家，诗论与纪乱诗成就突出。"},
    "关汉卿": {"dynasty": "元", "life_years": "约1220-约1300", "title": "", "brief": "元曲四大家之首。"},
    "马致远": {"dynasty": "元", "life_years": "约1250-约1321", "title": "东篱", "brief": "元曲四大家之一。"},
    "白朴": {"dynasty": "元", "life_years": "1226-约1306", "title": "", "brief": "元曲四大家之一。"},
    "张养浩": {"dynasty": "元", "life_years": "1270-1329", "title": "", "brief": "元代散曲家。"},
    "萨都剌": {"dynasty": "元", "life_years": "约1272-1355", "title": "", "brief": "元代诗人。"},
    "高启": {"dynasty": "明", "life_years": "1336-1374", "title": "", "brief": "明初诗人，诗才富健。"},
    "于谦": {"dynasty": "明", "life_years": "1398-1457", "title": "", "brief": "明代名臣，《石灰吟》传颂千古。"},
    "唐寅": {"dynasty": "明", "life_years": "1470-1523", "title": "六如居士", "brief": "明代书画家、文学家，吴中四才子之一。"},
    "文征明": {"dynasty": "明", "life_years": "1470-1559", "title": "", "brief": "明代书画家、文学家。"},
    "杨慎": {"dynasty": "明", "life_years": "1488-1559", "title": "升庵", "brief": "明代文学家，学问渊博，词曲亦工。"},
    "李贽": {"dynasty": "明", "life_years": "1527-1602", "title": "", "brief": "明代思想家、文学家。"},
    "袁宏道": {"dynasty": "明", "life_years": "1568-1610", "title": "", "brief": "明代公安派代表，文风清新。"},
    "张岱": {"dynasty": "明", "life_years": "1597-约1680", "title": "", "brief": "明末清初文学家，小品文成就很高。"},
    "钱谦益": {"dynasty": "清", "life_years": "1582-1664", "title": "", "brief": "明末清初诗人、学者。"},
    "吴伟业": {"dynasty": "清", "life_years": "1609-1671", "title": "梅村", "brief": "清初诗人，长篇歌行著名。"},
    "顾炎武": {"dynasty": "清", "life_years": "1613-1682", "title": "", "brief": "明末清初思想家、学者。"},
    "王士祯": {"dynasty": "清", "life_years": "1634-1711", "title": "渔洋", "brief": "清初诗坛领袖，神韵说代表。"},
    "纳兰性德": {"dynasty": "清", "life_years": "1655-1685", "title": "容若", "brief": "清代词人。"},
    "赵翼": {"dynasty": "清", "life_years": "1727-1814", "title": "", "brief": "清代史学家、诗人。"},
    "袁枚": {"dynasty": "清", "life_years": "1716-1797", "title": "随园", "brief": "清代诗人，性灵说代表。"},
    "郑燮": {"dynasty": "清", "life_years": "1693-1765", "title": "板桥", "brief": "清代书画家、文学家。"},
    "龚自珍": {"dynasty": "清", "life_years": "1792-1841", "title": "", "brief": "清代思想家、诗人。"},
    "黄遵宪": {"dynasty": "清", "life_years": "1848-1905", "title": "", "brief": "近代诗人，诗界革命代表。"},
    "秋瑾": {"dynasty": "清", "life_years": "1875-1907", "title": "鉴湖女侠", "brief": "近代民主革命志士、女诗人。"},
    "毛泽东": {"dynasty": "现代", "life_years": "1893-1976", "title": "", "brief": "现代革命家与诗人。"},
    "鲁迅": {"dynasty": "现代", "life_years": "1881-1936", "title": "", "brief": "现代文学家、思想家，旧体诗亦有力作。"},
}


def load_json(name: str):
    return json.loads((ASSETS / name).read_text(encoding="utf-8"))


def slug_name(name: str) -> str:
    # reuse simple hash fallback; prefer readable for known
    known = {
        **{k: re.sub(r"[^a-z0-9]", "", __import__("unicodedata").normalize("NFKD", k).encode("ascii", "ignore").decode() or "") for k in []},
    }
    # stable hex id
    return "a_" + name.encode("utf-8").hex()[:18]


def yaml_quote(s: str) -> str:
    if s is None:
        return '""'
    return json.dumps(s, ensure_ascii=False)


def parse_poem_blocks(text: str) -> tuple[str, list[str]]:
    """Return (header, list of poem block strings starting with '- id:')."""
    lines = text.splitlines(keepends=True)
    header: list[str] = []
    blocks: list[str] = []
    i = 0
    while i < len(lines) and not lines[i].startswith("- id:"):
        header.append(lines[i])
        i += 1
    while i < len(lines):
        if not lines[i].startswith("- id:"):
            # trailing junk
            break
        b = [lines[i]]
        i += 1
        while i < len(lines) and not lines[i].startswith("- id:"):
            b.append(lines[i])
            i += 1
        blocks.append("".join(b))
    return "".join(header), blocks


def block_field(block: str, key: str) -> str:
    m = re.search(rf"(?m)^  {re.escape(key)}: (.*)$", block)
    if not m:
        return ""
    v = m.group(1).strip()
    if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
        try:
            return json.loads(v) if v.startswith('"') else v[1:-1]
        except Exception:
            return v.strip("\"'")
    return v


def block_tags(block: str) -> list[str]:
    m = re.search(r"(?ms)^  tags:\n((?:  - .+\n?)*)", block)
    if not m:
        return []
    return [ln[4:].strip().strip("\"'") for ln in m.group(1).splitlines() if ln.startswith("  - ")]


def block_id(block: str) -> str:
    m = re.search(r"(?m)^- id: (\S+)", block)
    return m.group(1) if m else ""


def chinese_len(content: str) -> int:
    return sum(1 for c in content if "一" <= c <= "鿿")


def score_explore_for_extended(block: str, taken_titles: set[tuple[str, str]]) -> float:
    title = block_field(block, "title")
    author = block_field(block, "author")
    if (title, author) in taken_titles:
        return -1
    dynasty = block_field(block, "dynasty")
    tags = set(block_tags(block))
    content = block_field(block, "content")
    appr = block_field(block, "appreciation")
    score = 0.0
    if "古诗三百首" in tags:
        score += 8
    if "宋词三百首" in tags or "宋词精选" in tags:
        score += 8
    if "小学生必背古诗80首" in tags or "小学古诗" in tags or "初中古诗" in tags:
        score += 5
    if "最美" in tags:
        score += 2
    if dynasty in ("唐", "宋"):
        score += 2
    elif dynasty in ("五代", "元", "明", "清", "魏晋", "两汉", "先秦"):
        score += 1
    clen = chinese_len(content)
    if 16 <= clen <= 90:
        score += 2
    elif clen <= 120:
        score += 1
    if appr and "可作为拓展阅读" not in appr and "主题涉及" not in appr and len(appr) > 35:
        score += 3
    if block_field(block, "famous_lines") or "famous_lines:" in block:
        score += 1
    # prefer fewer "古诗词" only generic
    if tags - {"古诗词"}:
        score += 0.5
    return score


def promote_extended(need: int) -> tuple[int, int]:
    ext_path = SOURCES / "poems_extended.yaml"
    exp_path = SOURCES / "poems_explore.yaml"
    ext_header, ext_blocks = parse_poem_blocks(ext_path.read_text(encoding="utf-8"))
    exp_header, exp_blocks = parse_poem_blocks(exp_path.read_text(encoding="utf-8"))

    taken = set()
    for b in ext_blocks:
        taken.add((block_field(b, "title"), block_field(b, "author")))
    # also avoid core titles
    for p in load_json("poems_core.json"):
        taken.add((p["title"], p["author"]))

    max_num = 0
    for b in ext_blocks:
        m = re.search(r"poem_ext_(\d+)", block_id(b))
        if m:
            max_num = max(max_num, int(m.group(1)))

    scored: list[tuple[float, int, str]] = []
    for idx, b in enumerate(exp_blocks):
        s = score_explore_for_extended(b, taken)
        if s >= 4.0:
            scored.append((s, idx, b))
    scored.sort(key=lambda x: (-x[0], x[1]))

    pick = scored[:need]
    print(f"[extended] candidates score>=4: {len(scored)}, promote: {len(pick)} (need {need})")
    if not pick:
        return len(ext_blocks), len(exp_blocks)

    promote_idx = {idx for _, idx, _ in pick}
    new_ext_blocks = list(ext_blocks)
    new_exp_blocks = []
    next_num = max_num + 1

    for idx, b in enumerate(exp_blocks):
        if idx not in promote_idx:
            new_exp_blocks.append(b)
            continue
        new_id = f"poem_ext_{next_num:03d}"
        next_num += 1
        nb = b
        nb = re.sub(r"(?m)^- id: \S+", f"- id: {new_id}", nb, count=1)
        if re.search(r"(?m)^  layer:", nb):
            nb = re.sub(r"(?m)^  layer:.*$", "  layer: extended", nb, count=1)
        else:
            # insert after author/dynasty block - after id line area
            nb = re.sub(
                r"(?m)^(- id: \S+\n)",
                r"\1  layer: extended\n",
                nb,
                count=1,
            )
        # difficulty default if missing
        if not re.search(r"(?m)^  difficulty:", nb):
            nb = re.sub(r"(?m)^(  dynasty: .+\n)", r"\1  difficulty: 3\n", nb, count=1)
        # is_required
        if not re.search(r"(?m)^  is_required:", nb):
            nb = re.sub(r"(?m)^(  layer: extended\n)", r"\1  is_required: false\n", nb, count=1)
        # rewrite template-ish appreciation to extended tone
        title = block_field(nb, "title") or "无题"
        author = block_field(nb, "author") or "佚名"
        dynasty = block_field(nb, "dynasty") or "历代"
        tags = block_tags(nb)[:3]
        tag = "、".join(tags) if tags else "经典"
        appr = block_field(nb, "appreciation")
        if (not appr) or ("可作为拓展阅读" in appr) or ("主题涉及" in appr):
            new_appr = (
                f"《{title}》是{dynasty}{author}的名篇，主题涉及{tag}。"
                f"语言凝练，意境鲜明，适合反复诵读，体会情感与画面。"
            )
            if re.search(r"(?m)^  appreciation:", nb):
                nb = re.sub(
                    r"(?m)^  appreciation:.*$",
                    "  appreciation: " + yaml_quote(new_appr),
                    nb,
                    count=1,
                )
            else:
                nb = nb.rstrip() + f"\n  appreciation: {yaml_quote(new_appr)}\n"
        new_ext_blocks.append(nb if nb.endswith("\n") else nb + "\n")
        taken.add((title, author))

    ext_path.write_text(ext_header + "".join(new_ext_blocks), encoding="utf-8")
    exp_path.write_text(exp_header + "".join(new_exp_blocks), encoding="utf-8")
    print(f"[extended] now blocks={len(new_ext_blocks)}, explore={len(new_exp_blocks)}")
    return len(new_ext_blocks), len(new_exp_blocks)


def write_authors_yaml(authors: list[dict]) -> None:
    lines = [
        "# 作者信息种子数据（扩展覆盖：高频+中频作者）",
        "# tools/content_rebuild/expand_extended_authors.py",
        "",
        "authors:",
    ]
    for a in authors:
        lines.append(f"  - id: {a['id']}")
        lines.append(f"    name: {a['name']}")
        lines.append(f"    dynasty: {a['dynasty']}")
        lines.append(f"    life_years: {yaml_quote(a.get('life_years') or '')}")
        lines.append(f"    title: {yaml_quote(a.get('title') or '')}")
        lines.append(f"    brief: {yaml_quote(a.get('brief') or '')}")
        works = a.get("representative_works") or []
        if works:
            lines.append("    representative_works: [" + ", ".join(works) + "]")
        else:
            lines.append("    representative_works: []")
        lines.append(f"    avatar: {a.get('avatar') or 'default_avatar.png'}")
        lines.append("")
    (SOURCES / "authors_seed.yaml").write_text("\n".join(lines), encoding="utf-8")


def expand_authors() -> int:
    # Use current assets + will refresh after import; base on poem YAMLs via assets
    allp = []
    for n in ["poems_core.json", "poems_extended.json", "poems_explore.json"]:
        allp += load_json(n)
    # After promote, assets not yet updated — also scan yaml titles for authors from explore/extended files roughly via assets only.
    # We'll re-run author expansion after import in main.

    existing = {a["name"]: a for a in load_json("authors.json")}
    by_name = Counter(p.get("author") for p in allp)
    poems_by = {}
    dynasty_by = {}
    for p in allp:
        name = p.get("author") or "佚名"
        poems_by.setdefault(name, []).append(p["id"])
        if name not in dynasty_by and p.get("dynasty"):
            dynasty_by[name] = p["dynasty"]

    authors: dict[str, dict] = {}
    for name, a in existing.items():
        authors[name] = {
            "id": a["id"],
            "name": name,
            "dynasty": a.get("dynasty") or dynasty_by.get(name, "未知"),
            "life_years": a.get("life_years") or "",
            "title": a.get("title") or "",
            "brief": a.get("brief") or "",
            "representative_works": (a.get("representative_works") or poems_by.get(name, []))[:6],
            "avatar": a.get("avatar") or "default_avatar.png",
        }

    for name, count in by_name.most_common():
        if name in authors:
            authors[name]["representative_works"] = poems_by.get(name, [])[:6]
            continue
        if count < MIN_AUTHOR_POEMS:
            continue
        meta = EXTRA_AUTHORS.get(name)
        if meta is None:
            dyn = dynasty_by.get(name, "历代")
            meta = {
                "dynasty": dyn,
                "life_years": "",
                "title": "",
                "brief": f"{dyn}诗人/文学家。本应用收录其相关作品 {count} 首，可供诵读欣赏。",
            }
        authors[name] = {
            "id": f"author_{slug_name(name)}",
            "name": name,
            "dynasty": meta.get("dynasty") or dynasty_by.get(name, "未知"),
            "life_years": meta.get("life_years") or "",
            "title": meta.get("title") or "",
            "brief": meta.get("brief") or "",
            "representative_works": poems_by.get(name, [])[:6],
            "avatar": "default_avatar.png",
        }

    ordered = sorted(authors.values(), key=lambda a: (-by_name.get(a["name"], 0), a["name"]))
    write_authors_yaml(ordered)
    cov = sum(by_name[n] for n in authors if n in by_name)
    print(f"[authors] {len(ordered)} authors, coverage {cov}/{len(allp)} ({100*cov/len(allp):.1f}%)")
    return len(ordered)


def expand_authors_after_import() -> int:
    """Second pass using refreshed JSON."""
    return expand_authors()


def main() -> None:
    ext_n = len(load_json("poems_extended.json"))
    need = max(0, TARGET_EXTENDED - ext_n)
    print(f"extended now {ext_n}, need +{need} to reach {TARGET_EXTENDED}")
    promote_extended(need)
    expand_authors()
    print("next: import-all && validate, then re-run author pass if needed")


if __name__ == "__main__":
    main()
