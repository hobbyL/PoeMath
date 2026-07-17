#!/usr/bin/env python3
"""
开发期内容重建（无用户迁移约束）：
1. 扩写 authors_seed.yaml（高频作者）
2. 扩写 formulas.yaml 至 60+ 并尽量补 params
3. 替换 extended/explore 模板赏析为差异化短赏析
4. 不改动 poems_core 课标结构

用法（项目根）:
  python3 tools/content_rebuild/rebuild_assets.py
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

TEMPLATE_EXT = {
    "入选《唐诗三百首》的经典作品。",
    "入选《宋词精选》的经典作品。",
}
TEMPLATE_EXP = {
    "入选拓展层主题精选，由 yxcs/poems-db 原始数据整理。",
}


def load_json(name: str):
    return json.loads((ASSETS / name).read_text(encoding="utf-8"))


def slug_name(name: str) -> str:
    # keep CJK as-is in id via pinyin-ish simple map is hard; use ordinal hash-free roman
    # Prefer readable: author_<latin-ish>
    table = {
        "佚名": "yiming",
        "李商隐": "lishangyin",
        "吴文英": "wuwenying",
        "辛弃疾": "xinqiji",
        "杜牧": "dumu",
        "刘长卿": "liuchangqing",
        "韦应物": "weiyingwu",
        "刘禹锡": "liuyuxi",
        "李清照": "liqingzhao",
        "温庭筠": "wentingyun",
        "柳宗元": "liuzongyuan",
        "岑参": "cencan",
        "卢纶": "lulun",
        "张九龄": "zhangjiuling",
        "冯延巳": "fengyansi",
        "陈与义": "chenyuyi",
        "郑燮": "zhengxie",
        "崔颢": "cuihao",
        "李益": "liyi",
        "李煜": "liyu_n",
        "毛泽东": "maozedong",
        "纳兰性德": "nalanxingde",
        "高适": "gaoshi",
        "虞世南": "yushinan",
        "李颀": "liqi",
        "晏殊": "yanshu",
        "周邦彦": "zhoubangyan",
        "许浑": "xuhun",
        "袁去华": "yuanquhua",
        "欧阳修": "ouyangxiu",
        "孙光宪": "sunguangxian",
        "李贺": "lihe",
        "范仲淹": "fanzhongyan",
        "陈子昂": "chenziang",
        "司空曙": "sikongshu",
        "钱起": "qianqi",
        "汉乐府": "hanyuefu",
        "王勃": "wangbo",
        "杨炯": "yangjiong",
        "卢照邻": "luzhaolin",
        "宋之问": "songzhiwen",
        "沈佺期": "shenquanqi",
        "贺铸": "hezhu",
        "秦观": "qinguan",
        "黄庭坚": "huangtingjian",
        "姜夔": "jiangkui",
        "文天祥": "wentianxiang",
        "马致远": "mazhiyuan",
        "关汉卿": "guanhanqing",
        "白朴": "baipu",
        "张养浩": "zhangyanghao",
        "萨都剌": "sadula",
        "龚自珍": "gongzizhen",
        "秋瑾": "qiujin",
        "曹操": "caocao",
        "曹植": "caozhi",
        "陶渊明": "taoyuanming",
        "谢灵运": "xielingyun",
        "王翰": "wanghan",
        "王湾": "wangwan",
        "常建": "changjian",
        "张祜": "zhanghu",
        "贾岛": "jiadao",
        "孟郊": "mengjiao",
        "韩愈": "hanyu",
        "杜荀鹤": "duxunhe",
        "皮日休": "pirixiu",
        "韦庄": "weizhuang",
        "和凝": "heying",
        "柳永": "liuyong",
        "张先": "zhangxian",
        "晏几道": "yanjidao",
        "苏轼": "sushi",  # may already exist
        "陆游": "luyou",
        "杨万里": "yangwanli",
        "朱熹": "zhuxi",
        "岳飞": "yuefei",
        "文征明": "wenzhengming",
        "唐寅": "tangyin",
        "于谦": "yuqian",
        "张籍": "zhangji",
        "王建": "wangjian",
        "元稹": "yuanzhen",
        "白居易": "baijuyi",
        "杜甫": "dufu",
        "李白": "libai",
        "王维": "wangwei",
    }
    if name in table:
        return table[name]
    # fallback: hex of utf-8
    return "a_" + name.encode("utf-8").hex()[:16]


# Curated briefs for high-frequency missing authors (public knowledge, short).
AUTHOR_CATALOG: dict[str, dict] = {
    "佚名": {
        "dynasty": "先秦",
        "life_years": None,
        "title": "",
        "brief": "作者已佚名，多见于乐府民歌、民间歌谣与部分古诗辑录。语言质朴，情感真挚，是了解古代民间文学的重要窗口。",
    },
    "李商隐": {
        "dynasty": "唐",
        "life_years": "约813-约858",
        "title": "小李",
        "brief": "晚唐著名诗人，字义山，号玉溪生。诗风绮丽深情，善用典故，无题诗与咏史诗成就突出。代表作有《锦瑟》《夜雨寄北》等。",
    },
    "吴文英": {
        "dynasty": "宋",
        "life_years": "约1200-约1260",
        "title": "梦窗",
        "brief": "南宋词人，字君特，号梦窗。词风密丽深婉，结构精巧，与周邦彦并称。作品以慢词见长。",
    },
    "辛弃疾": {
        "dynasty": "宋",
        "life_years": "1140-1207",
        "title": "稼轩",
        "brief": "南宋豪放派词人，字幼安，号稼轩。词作气势雄健，兼具爱国情怀与田园闲适。代表作有《破阵子》《永遇乐·京口北固亭怀古》等。",
    },
    "杜牧": {
        "dynasty": "唐",
        "life_years": "803-约852",
        "title": "小杜",
        "brief": "晚唐诗人，字牧之。诗风俊爽清丽，咏史与七绝尤佳。代表作有《清明》《泊秦淮》《山行》等。",
    },
    "刘长卿": {
        "dynasty": "唐",
        "life_years": "约726-约786",
        "title": "",
        "brief": "中唐诗人，字文房。尤工五言，有「五言长城」之称。诗多写贬谪与山水，风格清冷。",
    },
    "韦应物": {
        "dynasty": "唐",
        "life_years": "737-约792",
        "title": "",
        "brief": "中唐诗人，诗风恬淡高远，多写山水田园与吏隐情怀。代表作有《滁州西涧》等。",
    },
    "刘禹锡": {
        "dynasty": "唐",
        "life_years": "772-842",
        "title": "诗豪",
        "brief": "中唐诗人、文学家，字梦得。诗风豪迈清新，咏史怀古与民歌体成就突出。代表作有《陋室铭》《竹枝词》《乌衣巷》等。",
    },
    "李清照": {
        "dynasty": "宋",
        "life_years": "1084-约1155",
        "title": "易安居士",
        "brief": "宋代女词人，号易安居士。早期清新婉约，南渡后多写家国身世之感。代表作有《如梦令》《声声慢》等。",
    },
    "温庭筠": {
        "dynasty": "唐",
        "life_years": "约812-约866",
        "title": "",
        "brief": "晚唐诗人、词人，花间词派重要代表。词风浓艳精美，对后世词体发展影响很大。",
    },
    "柳宗元": {
        "dynasty": "唐",
        "life_years": "773-819",
        "title": "柳河东",
        "brief": "中唐文学家，字子厚，与韩愈共同倡导古文运动。山水游记与寓言成就突出，诗风清峭。代表作有《江雪》《捕蛇者说》等。",
    },
    "岑参": {
        "dynasty": "唐",
        "life_years": "约715-770",
        "title": "",
        "brief": "盛唐边塞诗人，与高适并称。诗写边地风光与军旅生活，气势雄奇。代表作有《白雪歌送武判官归京》等。",
    },
    "卢纶": {
        "dynasty": "唐",
        "life_years": "约748-约799",
        "title": "大历十才子",
        "brief": "中唐诗人，大历十才子之一。边塞组诗《塞下曲》流传广泛。",
    },
    "张九龄": {
        "dynasty": "唐",
        "life_years": "678-740",
        "title": "",
        "brief": "盛唐政治家、诗人。诗风清雅醇正，以《望月怀远》等名篇著称。",
    },
    "冯延巳": {
        "dynasty": "五代",
        "life_years": "约903-960",
        "title": "",
        "brief": "南唐词人，词风细腻感伤，对北宋词影响深远。代表作有《鹊踏枝》等。",
    },
    "陈与义": {
        "dynasty": "宋",
        "life_years": "1090-1138",
        "title": "简斋",
        "brief": "南北宋之交诗人，江西诗派重要人物。诗风由清新转向沉郁，南渡后多家国之叹。",
    },
    "郑燮": {
        "dynasty": "清",
        "life_years": "1693-1765",
        "title": "郑板桥",
        "brief": "清代书画家、文学家，「扬州八怪」之一。诗书画三绝，题画诗与民本关怀并存。",
    },
    "崔颢": {
        "dynasty": "唐",
        "life_years": "约704-754",
        "title": "",
        "brief": "盛唐诗人。《黄鹤楼》被誉为唐人七律压卷之作，边塞诗亦有佳作。",
    },
    "李益": {
        "dynasty": "唐",
        "life_years": "748-约829",
        "title": "",
        "brief": "中唐边塞诗人，七绝尤工。诗写边愁征人，音节谐美。",
    },
    "李煜": {
        "dynasty": "五代",
        "life_years": "937-978",
        "title": "李后主",
        "brief": "南唐后主，词人。前期多写宫廷生活，亡国后词作沉痛真挚，语言自然。代表作有《虞美人》《相见欢》等。",
    },
    "毛泽东": {
        "dynasty": "现代",
        "life_years": "1893-1976",
        "title": "",
        "brief": "中国现代伟大的无产阶级革命家、战略家与诗人。诗词气魄雄浑，富于革命浪漫主义色彩。",
    },
    "纳兰性德": {
        "dynasty": "清",
        "life_years": "1655-1685",
        "title": "纳兰容若",
        "brief": "清代满族词人，词风清新婉丽，哀感顽艳。代表作有《木兰花·拟古决绝词》等。",
    },
    "高适": {
        "dynasty": "唐",
        "life_years": "约700-765",
        "title": "",
        "brief": "盛唐边塞诗人，与岑参并称。诗风雄浑悲壮，代表作有《燕歌行》等。",
    },
    "虞世南": {
        "dynasty": "唐",
        "life_years": "558-638",
        "title": "",
        "brief": "唐初书法家、诗人，书法与欧阳询、褚遂良等齐名。诗作典雅清丽。",
    },
    "李颀": {
        "dynasty": "唐",
        "life_years": "约690-约751",
        "title": "",
        "brief": "盛唐诗人，边塞与音乐题材诗著名。代表作有《古从军行》等。",
    },
    "晏殊": {
        "dynasty": "宋",
        "life_years": "991-1055",
        "title": "晏元献",
        "brief": "北宋词人、政治家。词风温润闲雅，多写时光流逝与离愁。代表作有《浣溪沙》等。",
    },
    "周邦彦": {
        "dynasty": "宋",
        "life_years": "1056-1121",
        "title": "清真居士",
        "brief": "北宋词人，格律精严，被誉为「词中老杜」。对后世格律词派影响极大。",
    },
    "许浑": {
        "dynasty": "唐",
        "life_years": "约791-约858",
        "title": "",
        "brief": "晚唐诗人，律诗圆熟，多写登临怀古与水乡风光。",
    },
    "袁去华": {
        "dynasty": "宋",
        "life_years": "生卒年不详",
        "title": "",
        "brief": "南宋词人，词风清丽，多写羁旅与离情。",
    },
    "欧阳修": {
        "dynasty": "宋",
        "life_years": "1007-1072",
        "title": "醉翁",
        "brief": "北宋文坛领袖，唐宋八大家之一。诗、词、文兼擅，词风清新疏宕。代表作有《醉翁亭记》《生查子》等。",
    },
    "孙光宪": {
        "dynasty": "五代",
        "life_years": "约900-968",
        "title": "",
        "brief": "五代词人，花间词派重要作者之一，词作题材较广。",
    },
    "李贺": {
        "dynasty": "唐",
        "life_years": "约790-约816",
        "title": "诗鬼",
        "brief": "中唐诗人，想象奇诡，语言冷艳，有「诗鬼」之称。代表作有《李凭箜篌引》等。",
    },
    "范仲淹": {
        "dynasty": "宋",
        "life_years": "989-1052",
        "title": "",
        "brief": "北宋名臣、文学家。词作苍凉悲壮，散文《岳阳楼记》以「先天下之忧而忧」传世。",
    },
    "陈子昂": {
        "dynasty": "唐",
        "life_years": "661-702",
        "title": "",
        "brief": "初唐诗人，倡导汉魏风骨，反对齐梁绮靡。代表作有《登幽州台歌》。",
    },
    "司空曙": {
        "dynasty": "唐",
        "life_years": "约720-约790",
        "title": "大历十才子",
        "brief": "中唐诗人，大历十才子之一。诗多写羁旅友情，风格清雅。",
    },
    "钱起": {
        "dynasty": "唐",
        "life_years": "约722-约780",
        "title": "大历十才子",
        "brief": "中唐诗人，大历十才子之一。诗风清奇，写景细致。",
    },
    "汉乐府": {
        "dynasty": "汉",
        "life_years": None,
        "title": "乐府",
        "brief": "汉代乐府机关采集与创作的诗歌总称，题材广泛，语言质朴，叙事性强，对后世诗歌影响深远。",
    },
    "王勃": {
        "dynasty": "唐",
        "life_years": "约650-约676",
        "title": "初唐四杰",
        "brief": "初唐四杰之首，诗文清新刚健。代表作有《滕王阁序》《送杜少府之任蜀州》。",
    },
    "陶渊明": {
        "dynasty": "东晋",
        "life_years": "约365-427",
        "title": "靖节先生",
        "brief": "东晋大诗人，田园诗派开创者。诗风自然冲淡，代表作有《饮酒》《归园田居》等。",
    },
    "曹操": {
        "dynasty": "汉末",
        "life_years": "155-220",
        "title": "魏武帝",
        "brief": "东汉末年政治家、军事家、诗人。诗风慷慨悲凉，代表作有《观沧海》《龟虽寿》等。",
    },
    "曹植": {
        "dynasty": "三国",
        "life_years": "192-232",
        "title": "陈思王",
        "brief": "三国魏诗人，曹操之子。才思敏捷，五言诗成就很高，代表作有《七步诗》《洛神赋》等。",
    },
    "马致远": {
        "dynasty": "元",
        "life_years": "约1250-约1321",
        "title": "东篱",
        "brief": "元曲四大家之一。散曲《天净沙·秋思》被誉为「秋思之祖」。",
    },
    "关汉卿": {
        "dynasty": "元",
        "life_years": "约1220-约1300",
        "title": "",
        "brief": "元代戏曲家，「元曲四大家」之首。剧作深刻反映社会现实，代表作有《窦娥冤》等。",
    },
    "柳永": {
        "dynasty": "宋",
        "life_years": "约984-约1053",
        "title": "柳七",
        "brief": "北宋词人，慢词大家。词写市井与羁旅，语言通俗，流传极广。代表作有《雨霖铃》等。",
    },
    "秦观": {
        "dynasty": "宋",
        "life_years": "1049-1100",
        "title": "淮海居士",
        "brief": "北宋词人，苏门四学士之一。词风婉约清丽，多写爱情与贬谪之感。",
    },
    "姜夔": {
        "dynasty": "宋",
        "life_years": "约1155-约1221",
        "title": "白石道人",
        "brief": "南宋词人、音乐家。词风清空骚雅，自度曲成就突出。",
    },
    "文天祥": {
        "dynasty": "宋",
        "life_years": "1236-1283",
        "title": "文山",
        "brief": "南宋末大臣、文学家。诗作充满爱国正气，代表作有《过零丁洋》《正气歌》。",
    },
    "岳飞": {
        "dynasty": "宋",
        "life_years": "1103-1142",
        "title": "",
        "brief": "南宋抗金名将。词《满江红》气壮山河，流传千古。",
    },
    "韩愈": {
        "dynasty": "唐",
        "life_years": "768-824",
        "title": "韩昌黎",
        "brief": "中唐文学家，唐宋八大家之首，倡导古文运动。诗风奇崛，文以载道。",
    },
    "贾岛": {
        "dynasty": "唐",
        "life_years": "779-843",
        "title": "",
        "brief": "中唐诗人，以苦吟著称，「推敲」典故与之相关。诗风清奇僻苦。",
    },
    "孟郊": {
        "dynasty": "唐",
        "life_years": "751-814",
        "title": "",
        "brief": "中唐诗人，与贾岛并称「郊寒岛瘦」。诗多写世态炎凉与贫士悲慨。",
    },
    "王翰": {
        "dynasty": "唐",
        "life_years": "生卒年不详",
        "title": "",
        "brief": "盛唐边塞诗人。《凉州词》「葡萄美酒夜光杯」传诵极广。",
    },
    "常建": {
        "dynasty": "唐",
        "life_years": "生卒年不详",
        "title": "",
        "brief": "盛唐诗人，山水田园与边塞题材兼擅。《题破山寺后禅院》以「曲径通幽」著称。",
    },
    "张祜": {
        "dynasty": "唐",
        "life_years": "约785-约849",
        "title": "",
        "brief": "中晚唐诗人，宫词与山水小诗清俊可诵。",
    },
    "王湾": {
        "dynasty": "唐",
        "life_years": "生卒年不详",
        "title": "",
        "brief": "盛唐诗人。《次北固山下》「海日生残夜，江春入旧年」为千古名句。",
    },
    "黄庭坚": {
        "dynasty": "宋",
        "life_years": "1045-1105",
        "title": "山谷道人",
        "brief": "北宋诗人、书法家，江西诗派开山之祖。诗风生新瘦硬。",
    },
    "晏几道": {
        "dynasty": "宋",
        "life_years": "1038-1110",
        "title": "小山",
        "brief": "北宋词人，晏殊幼子。词风婉丽感伤，多写恋情与追忆。",
    },
    "张先": {
        "dynasty": "宋",
        "life_years": "990-1078",
        "title": "张三影",
        "brief": "北宋词人，以善用「影」字著称，词风清丽。",
    },
    "贺铸": {
        "dynasty": "宋",
        "life_years": "1052-1125",
        "title": "贺方回",
        "brief": "北宋词人，词风刚柔兼济，《青玉案》等名篇流传。",
    },
    "龚自珍": {
        "dynasty": "清",
        "life_years": "1792-1841",
        "title": "",
        "brief": "清代思想家、诗人。诗风雄奇，富有社会批判精神。代表作有《己亥杂诗》。",
    },
    "秋瑾": {
        "dynasty": "清",
        "life_years": "1875-1907",
        "title": "鉴湖女侠",
        "brief": "近代民主革命志士、女诗人。诗词慷慨激昂，充满爱国热情。",
    },
    "张养浩": {
        "dynasty": "元",
        "life_years": "1270-1329",
        "title": "",
        "brief": "元代散曲家。代表作《山坡羊·潼关怀古》以「兴，百姓苦」警世。",
    },
    "白朴": {
        "dynasty": "元",
        "life_years": "1226-约1306",
        "title": "",
        "brief": "元曲四大家之一，杂剧与散曲兼擅。",
    },
    "萨都剌": {
        "dynasty": "元",
        "life_years": "约1272-1355",
        "title": "",
        "brief": "元代诗人，诗风清丽，边塞与山水题材出色。",
    },
    "韦庄": {
        "dynasty": "唐",
        "life_years": "约836-910",
        "title": "",
        "brief": "晚唐五代诗人、词人。诗写乱离，词开花间清丽一派。",
    },
    "杜荀鹤": {
        "dynasty": "唐",
        "life_years": "846-904",
        "title": "",
        "brief": "晚唐诗人，诗风质朴，多写民生疾苦。",
    },
    "王建": {
        "dynasty": "唐",
        "life_years": "约767-约830",
        "title": "",
        "brief": "中唐诗人，以宫词与乐府著称，反映社会百态。",
    },
    "张籍": {
        "dynasty": "唐",
        "life_years": "约766-约830",
        "title": "",
        "brief": "中唐诗人，乐府诗反映现实，与王建并称。",
    },
    "杨炯": {
        "dynasty": "唐",
        "life_years": "650-约693",
        "title": "初唐四杰",
        "brief": "初唐四杰之一，边塞诗刚健有力。",
    },
    "卢照邻": {
        "dynasty": "唐",
        "life_years": "约634-约689",
        "title": "初唐四杰",
        "brief": "初唐四杰之一，诗风清峻，代表作有《长安古意》。",
    },
    "谢灵运": {
        "dynasty": "南朝宋",
        "life_years": "385-433",
        "title": "",
        "brief": "南朝山水诗开创者。诗写自然景物精细生动，对唐诗影响很大。",
    },
}


def yaml_escape(s: str) -> str:
    if s is None:
        return '""'
    if any(c in s for c in ':#{}[],&*?|>!%@`\'"\n') or s.startswith(" ") or s.endswith(" "):
        return json.dumps(s, ensure_ascii=False)
    return s


def write_authors(path: Path, authors: list[dict]) -> None:
    lines = [
        "# 作者信息种子数据（内容重建：高频作者覆盖）",
        "# 由 tools/content_rebuild/rebuild_assets.py 生成/合并",
        "",
        "authors:",
    ]
    for a in authors:
        lines.append(f"  - id: {a['id']}")
        lines.append(f"    name: {a['name']}")
        lines.append(f"    dynasty: {a['dynasty']}")
        ly = a.get("life_years")
        lines.append(f"    life_years: {yaml_escape(ly) if ly else '\"\"'}")
        lines.append(f"    title: {yaml_escape(a.get('title') or '')}")
        lines.append(f"    brief: {yaml_escape(a.get('brief') or '')}")
        works = a.get("representative_works") or []
        if works:
            w = ", ".join(works)
            lines.append(f"    representative_works: [{w}]")
        else:
            lines.append("    representative_works: []")
        lines.append(f"    avatar: {a.get('avatar') or 'default_avatar.png'}")
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def rebuild_authors() -> int:
    existing_json = load_json("authors.json")
    allp = []
    for n in ["poems_core.json", "poems_extended.json", "poems_explore.json"]:
        allp += load_json(n)

    by_name = Counter(p.get("author") for p in allp)
    poems_by_author: dict[str, list[str]] = {}
    dynasty_by_author: dict[str, str] = {}
    for p in allp:
        name = p.get("author") or "佚名"
        poems_by_author.setdefault(name, []).append(p["id"])
        if name not in dynasty_by_author and p.get("dynasty"):
            dynasty_by_author[name] = p["dynasty"]

    # start from existing
    authors: dict[str, dict] = {}
    for a in existing_json:
        authors[a["name"]] = {
            "id": a["id"],
            "name": a["name"],
            "dynasty": a.get("dynasty") or dynasty_by_author.get(a["name"], "未知"),
            "life_years": a.get("life_years") or "",
            "title": a.get("title") or "",
            "brief": a.get("brief") or "",
            "representative_works": (a.get("representative_works") or [])[:6],
            "avatar": a.get("avatar") or "default_avatar.png",
        }

    # add top authors by poem count
    for name, count in by_name.most_common():
        if name in authors:
            # refresh works with real ids
            works = poems_by_author.get(name, [])[:6]
            if works:
                authors[name]["representative_works"] = works
            continue
        if count < 2 and name not in AUTHOR_CATALOG:
            # skip ultra rare unless curated
            continue
        if name not in AUTHOR_CATALOG and count < 3:
            continue
        meta = AUTHOR_CATALOG.get(name)
        if meta is None:
            # generic stub for remaining mid-frequency
            if count < 4:
                continue
            meta = {
                "dynasty": dynasty_by_author.get(name, "未知"),
                "life_years": "",
                "title": "",
                "brief": f"{dynasty_by_author.get(name, '历代')}文学家/诗人。作品收录于本应用诗词库，共 {count} 首相关篇目，可供诵读与欣赏。",
            }
        authors[name] = {
            "id": f"author_{slug_name(name)}",
            "name": name,
            "dynasty": meta.get("dynasty") or dynasty_by_author.get(name, "未知"),
            "life_years": meta.get("life_years") or "",
            "title": meta.get("title") or "",
            "brief": meta.get("brief") or "",
            "representative_works": poems_by_author.get(name, [])[:6],
            "avatar": "default_avatar.png",
        }

    # stable sort: by poem count desc then name
    ordered = sorted(
        authors.values(),
        key=lambda a: (-by_name.get(a["name"], 0), a["name"]),
    )
    write_authors(SOURCES / "authors_seed.yaml", ordered)
    covered = sum(by_name[n] for n in authors if n in by_name)
    print(f"[authors] {len(ordered)} authors, poem coverage {covered}/{len(allp)}")
    return len(ordered)


EXTRA_FORMULAS = """
  # ---------- 内容重建追加（目标 60+）----------
  - id: formula_area_rhombus
    category: 几何面积
    name: 菱形面积
    formula_text: S = a × h = (d1 × d2) ÷ 2
    formula_latex: "S = a h = \\\\frac{d_1 d_2}{2}"
    grade: 5
    params:
      - {symbol: S, meaning: 面积}
      - {symbol: a, meaning: 边长}
      - {symbol: h, meaning: 对应高}
      - {symbol: d1, meaning: 一条对角线}
      - {symbol: d2, meaning: 另一条对角线}
    memory_tip: 可看成底乘高；也可用对角线乘积的一半。
    example: 对角线 6 cm、8 cm，面积 = 6×8÷2 = 24 cm²。
    related_formulas: [formula_area_parallelogram]

  - id: formula_area_sector
    category: 几何面积
    name: 扇形面积
    formula_text: S = (n/360) × π × r²
    formula_latex: "S = \\\\frac{n}{360}\\\\pi r^2"
    grade: 6
    params:
      - {symbol: S, meaning: 扇形面积}
      - {symbol: n, meaning: 圆心角度数}
      - {symbol: r, meaning: 半径}
    memory_tip: 扇形是圆的一部分，占 n/360。
    example: 半径 6、圆心角 90°，面积 = 90/360×3.14×36 = 28.26。
    related_formulas: [formula_area_circle, formula_arc_length]

  - id: formula_arc_length
    category: 几何周长
    name: 弧长
    formula_text: l = (n/360) × 2πr
    formula_latex: "l = \\\\frac{n}{360} \\\\times 2\\\\pi r"
    grade: 6
    params:
      - {symbol: l, meaning: 弧长}
      - {symbol: n, meaning: 圆心角度数}
      - {symbol: r, meaning: 半径}
    memory_tip: 弧长是圆周长的 n/360。
    example: r=5、n=72°，弧长 = 72/360×2×3.14×5 = 6.28。
    related_formulas: [formula_perimeter_circle, formula_area_sector]

  - id: formula_area_ring
    category: 几何面积
    name: 圆环面积
    formula_text: S = π(R² − r²)
    formula_latex: "S = \\\\pi(R^2 - r^2)"
    grade: 6
    params:
      - {symbol: S, meaning: 圆环面积}
      - {symbol: R, meaning: 外圆半径}
      - {symbol: r, meaning: 内圆半径}
    memory_tip: 大圆面积减小圆面积。
    example: R=5、r=3，面积 = 3.14×(25-9)=50.24。
    related_formulas: [formula_area_circle]

  - id: formula_surface_cylinder
    category: 几何面积
    name: 圆柱侧面积与表面积
    formula_text: S侧 = 2πrh；S表 = 2πr(h+r)
    formula_latex: "S_{\\\\text{侧}}=2\\\\pi r h;\\ S_{\\\\text{表}}=2\\\\pi r(h+r)"
    grade: 6
    params:
      - {symbol: r, meaning: 底面半径}
      - {symbol: h, meaning: 高}
    memory_tip: 侧面展开是长方形，长是底面周长。
    example: r=2、h=5，侧面积 = 2×3.14×2×5=62.8。
    related_formulas: [formula_volume_cylinder, formula_perimeter_circle]

  - id: formula_triangle_sum
    category: 几何关系
    name: 三角形内角和
    formula_text: ∠A + ∠B + ∠C = 180°
    formula_latex: "\\\\angle A + \\\\angle B + \\\\angle C = 180^\\\\circ"
    grade: 4
    params:
      - {symbol: A/B/C, meaning: 三个内角}
    memory_tip: 三角形三个角加起来是平角。
    example: 两角 40°、60°，第三角 = 80°。
    related_formulas: [formula_triangle_sides]

  - id: formula_triangle_sides
    category: 几何关系
    name: 三角形三边关系
    formula_text: 两边之和大于第三边；两边之差小于第三边
    formula_latex: "a+b>c,\\ |a-b|<c"
    grade: 4
    params:
      - {symbol: a,b,c, meaning: 三边长}
    memory_tip: 能围成三角形，两边和必须大于第三边。
    example: 3、4、5 可以；1、2、3 不可以。
    related_formulas: [formula_triangle_sum]

  - id: formula_square_diagonal
    category: 几何关系
    name: 长方形/正方形对角线
    formula_text: 长方形对角线相等且互相平分
    formula_latex: "d_1 = d_2"
    grade: 4
    params:
      - {symbol: d, meaning: 对角线}
    memory_tip: 长方形对角线一样长，正方形还互相垂直。
    example: 长方形对角线都是 10 cm。
    related_formulas: [formula_area_rect, formula_area_square]

  - id: formula_avg
    category: 数量关系
    name: 平均数
    formula_text: 平均数 = 总数量 ÷ 总份数
    formula_latex: "\\\\bar{x} = \\\\frac{\\\\sum x}{n}"
    grade: 3
    params:
      - {symbol: 平均数, meaning: 平均后的结果}
      - {symbol: n, meaning: 份数}
    memory_tip: 总数除以份数。
    example: 3、5、7 的平均 = 15÷3 = 5。
    related_formulas: [formula_price]

  - id: formula_remainder
    category: 数量关系
    name: 有余数除法
    formula_text: 被除数 = 除数 × 商 + 余数（0 ≤ 余数 < 除数）
    formula_latex: "a = bq + r,\\ 0 \\\\le r < b"
    grade: 3
    params:
      - {symbol: a, meaning: 被除数}
      - {symbol: b, meaning: 除数}
      - {symbol: q, meaning: 商}
      - {symbol: r, meaning: 余数}
    memory_tip: 余数一定比除数小。
    example: 17÷5 = 3……2，因为 5×3+2=17。
    related_formulas: [formula_law_mul_commutative]

  - id: formula_decimal_add
    category: 分数小数
    name: 小数加减
    formula_text: 小数点对齐后按整数加减
    formula_latex: "a \\\\pm b"
    grade: 4
    params: []
    memory_tip: 小数点对齐，末尾可补 0。
    example: 3.5 + 1.25 = 4.75。
    related_formulas: [formula_decimal_mul]

  - id: formula_decimal_mul
    category: 分数小数
    name: 小数乘法
    formula_text: 按整数相乘，小数位数 = 因数小数位数之和
    formula_latex: "a \\\\times b"
    grade: 5
    params: []
    memory_tip: 先当整数乘，再点小数点。
    example: 1.2×0.3 = 0.36。
    related_formulas: [formula_decimal_div, formula_decimal_add]

  - id: formula_decimal_div
    category: 分数小数
    name: 小数除法
    formula_text: 除数化整数，被除数小数点同等移动
    formula_latex: "a \\\\div b"
    grade: 5
    params: []
    memory_tip: 除数变整数，被除数跟着挪小数点。
    example: 3.6÷0.4 = 36÷4 = 9。
    related_formulas: [formula_decimal_mul]

  - id: formula_fraction_basic
    category: 分数小数
    name: 分数基本性质
    formula_text: 分子分母同乘或同除一个不为 0 的数，分数大小不变
    formula_latex: "\\\\frac{a}{b}=\\\\frac{ak}{bk}"
    grade: 5
    params: []
    memory_tip: 上下同乘同除，大小不变（约分通分依据）。
    example: 1/2 = 2/4 = 3/6。
    related_formulas: [formula_fraction_add_diff_denom]

  - id: formula_reciprocal
    category: 分数小数
    name: 倒数
    formula_text: a 与 1/a 互为倒数（a≠0）；乘积为 1
    formula_latex: "a \\\\times \\\\frac{1}{a} = 1"
    grade: 6
    params: []
    memory_tip: 分子分母调个个，就是倒数。
    example: 3/4 的倒数是 4/3。
    related_formulas: [formula_fraction_divide]

  - id: formula_percent_three
    category: 比例
    name: 百分数三种量
    formula_text: 比较量 = 标准量 × 百分率；标准量 = 比较量 ÷ 百分率
    formula_latex: "a = b \\\\times p\\\\%"
    grade: 6
    params:
      - {symbol: a, meaning: 比较量}
      - {symbol: b, meaning: 标准量}
      - {symbol: p%, meaning: 百分率}
    memory_tip: 单位「1」× 百分率 = 对应数量。
    example: 80 的 25% 是 20。
    related_formulas: [formula_percentage, formula_ratio]

  - id: formula_scale
    category: 比例
    name: 比例尺
    formula_text: 比例尺 = 图上距离 ∶ 实际距离
    formula_latex: "\\\\text{比例尺}=\\\\text{图距}:\\\\text{实距}"
    grade: 6
    params: []
    memory_tip: 图上 1，实际是多少，写成分数或比。
    example: 1:100000 表示图上 1 cm 实际 1 km。
    related_formulas: [formula_ratio]

  - id: formula_direct_prop
    category: 比例
    name: 正比例
    formula_text: y/x = k（一定），y 与 x 成正比例
    formula_latex: "\\\\frac{y}{x}=k"
    grade: 6
    params:
      - {symbol: k, meaning: 比例系数}
    memory_tip: 一个量扩大几倍，另一个也扩大几倍。
    example: 速度一定时，路程与时间成正比例。
    related_formulas: [formula_inverse_prop, formula_speed]

  - id: formula_inverse_prop
    category: 比例
    name: 反比例
    formula_text: x × y = k（一定），y 与 x 成反比例
    formula_latex: "xy=k"
    grade: 6
    params:
      - {symbol: k, meaning: 积一定}
    memory_tip: 一个量扩大，另一个反而缩小。
    example: 路程一定时，速度与时间成反比例。
    related_formulas: [formula_direct_prop, formula_speed]

  - id: formula_simple_equation
    category: 数量关系
    name: 简易方程
    formula_text: 使等式左右相等的未知数的值叫解
    formula_latex: "ax+b=c"
    grade: 5
    params:
      - {symbol: x, meaning: 未知数}
    memory_tip: 等式两边同时加减乘除同一个数（除数不为 0）。
    example: 2x+3=11 → 2x=8 → x=4。
    related_formulas: [formula_law_distributive]

  - id: formula_interest
    category: 数量关系
    name: 利息
    formula_text: 利息 = 本金 × 利率 × 时间
    formula_latex: "I = P \\\\times r \\\\times t"
    grade: 6
    params:
      - {symbol: I, meaning: 利息}
      - {symbol: P, meaning: 本金}
      - {symbol: r, meaning: 利率}
      - {symbol: t, meaning: 时间}
    memory_tip: 本金乘利率再乘存的时间。
    example: 本金 1000 元，年利率 2%，存 1 年利息 20 元。
    related_formulas: [formula_percentage]

  - id: formula_discount
    category: 数量关系
    name: 折扣
    formula_text: 折后价 = 原价 × 折扣
    formula_latex: "\\\\text{折后价}=\\\\text{原价}\\\\times\\\\text{折扣}"
    grade: 6
    params: []
    memory_tip: 八折就是 ×0.8；打六折就是 ×0.6。
    example: 200 元打八折 = 160 元。
    related_formulas: [formula_percentage, formula_price]

  - id: formula_tree_planting
    category: 数量关系
    name: 植树问题
    formula_text: 两端都栽：棵数 = 段数 + 1；一端栽：棵数 = 段数；两端不栽：棵数 = 段数 − 1
    formula_latex: "n_{\\\\text{棵}} = n_{\\\\text{段}} \\\\pm 1"
    grade: 5
    params: []
    memory_tip: 先分清两端栽不栽，再数间隔。
    example: 全长 20 m，每隔 5 m 栽一棵且两端栽，棵数 = 4+1=5。
    related_formulas: [formula_enclosure]

  - id: formula_enclosure
    category: 数量关系
    name: 方阵/围边问题
    formula_text: 最外层人数 ≈ 4×(边长 − 1)（正方形方阵）
    formula_latex: "4(n-1)"
    grade: 5
    params: []
    memory_tip: 四边都要数，角上的人别重复。
    example: 每边 10 人的空心方阵最外层 36 人。
    related_formulas: [formula_tree_planting]

  - id: formula_age
    category: 数量关系
    name: 年龄问题
    formula_text: 两人年龄差不变；年龄和随时间增加
    formula_latex: "a-b=\\\\text{常数}"
    grade: 4
    params: []
    memory_tip: 年龄差不变是突破口。
    example: 爸爸比儿子大 28 岁，永远大 28 岁。
    related_formulas: [formula_avg]

  - id: formula_angle_types
    category: 几何关系
    name: 角的分类
    formula_text: 锐角 < 90°；直角 = 90°；钝角 90°–180°；平角 = 180°；周角 = 360°
    formula_latex: "90^\\\\circ,\\ 180^\\\\circ,\\ 360^\\\\circ"
    grade: 4
    params: []
    memory_tip: 直角三角板是 90°，平角像一条直线。
    example: 120° 是钝角。
    related_formulas: [formula_triangle_sum]

  - id: formula_volume_capacity
    category: 单位换算
    name: 容积与体积
    formula_text: 容积 ≈ 容器内部体积；1 L = 1 dm³；1 mL = 1 cm³
    formula_latex: "1\\\\,\\\\text{L}=1\\\\,\\\\text{dm}^3"
    grade: 5
    params: []
    memory_tip: 装水的本领叫容积，单位常用升、毫升。
    example: 矿泉水 500 mL = 500 cm³。
    related_formulas: [formula_volume_units]

  - id: formula_area_units_mu
    category: 单位换算
    name: 土地面积单位
    formula_text: 1 公顷 = 10000 m² = 15 亩；1 亩 ≈ 666.7 m²
    formula_latex: "1\\\\,\\\\text{公顷}=10000\\\\,\\\\text{m}^2"
    grade: 4
    params: []
    memory_tip: 公顷很大，边长 100 m 的正方形是 1 公顷。
    example: 2 公顷 = 30000 m²。
    related_formulas: [formula_area_units]

  - id: formula_ops_order
    category: 运算定律
    name: 四则运算顺序
    formula_text: 先乘除后加减；有括号先算括号
    formula_latex: "(a+b)\\\\times c"
    grade: 3
    params: []
    memory_tip: 括号→乘除→加减；同级从左到右。
    example: 3+4×5 = 3+20 = 23。
    related_formulas: [formula_law_distributive]

  - id: formula_factor_multiple
    category: 数量关系
    name: 因数与倍数
    formula_text: 如果 a÷b=c（整除），则 a 是 b 的倍数，b 是 a 的因数
    formula_latex: "a=bc"
    grade: 5
    params: []
    memory_tip: 能整除才能说倍数、因数。
    example: 12 的因数有 1,2,3,4,6,12。
    related_formulas: [formula_remainder]

  - id: formula_gcd_lcm_idea
    category: 数量关系
    name: 公因数与公倍数
    formula_text: 公因数：几个数共有的因数；公倍数：共有的倍数
    formula_latex: "\\\\gcd,\\ \\\\operatorname{lcm}"
    grade: 5
    params: []
    memory_tip: 求最大公因数、最小公倍数，可列因数或短除法。
    example: 12 与 18 的最大公因数是 6，最小公倍数是 36。
    related_formulas: [formula_factor_multiple]
"""


def append_formulas() -> int:
    path = SOURCES / "formulas.yaml"
    text = path.read_text(encoding="utf-8")
    if "formula_area_rhombus" in text:
        print("[formulas] extra formulas already present, skip append")
    else:
        # update header count comment
        text = re.sub(
            r"共 \\d+ 条示例.*",
            "共 60+ 条（内容重建扩充）",
            text,
            count=1,
        )
        if not text.endswith("\n"):
            text += "\n"
        text += EXTRA_FORMULAS
        path.write_text(text, encoding="utf-8")

    # count formulas in yaml roughly
    count = len(re.findall(r"^\\s*- id: formula_", text, flags=re.M))
    print(f"[formulas] yaml formula entries ≈ {count}")
    return count


def short_appreciation(title: str, author: str, dynasty: str, tags: list[str], layer: str) -> str:
    tag = "、".join(tags[:3]) if tags else "经典"
    dyn = dynasty or "历代"
    auth = author or "佚名"
    if layer == "extended":
        return f"《{title}》是{dyn}{auth}的名篇，主题涉及{tag}。语言凝练，意境鲜明，适合反复诵读，体会情感与画面。"
    return f"《{title}》属{dyn}作品（{auth}），围绕{tag}等主题展开。可作为拓展阅读，感受不同时代的诗情与表达。"


def patch_poems_yaml(path: Path, templates: set[str], layer: str) -> int:
    text = path.read_text(encoding="utf-8")
    # split by poem entries starting with "- id:"
    parts = re.split(r"(?m)^(- id: )", text)
    # parts[0] is header before first poem; then pairs (delimiter, body)
    if len(parts) < 3:
        print(f"[poems] {path.name}: no poems found")
        return 0

    header = parts[0]
    out = [header]
    changed = 0
    i = 1
    while i < len(parts):
        delim = parts[i]
        body = parts[i + 1]
        block = delim + body

        m_appr = re.search(r"(?m)^(  appreciation: )(.*)$", block)
        if m_appr:
            raw_val = m_appr.group(2).strip()
            # unquote if quoted
            val = raw_val
            if (val.startswith('"') and val.endswith('"')) or (
                val.startswith("'") and val.endswith("'")
            ):
                val = val[1:-1]
            if val in templates:
                title_m = re.search(r"(?m)^  title: (.+)$", block)
                author_m = re.search(r"(?m)^  author: (.+)$", block)
                dynasty_m = re.search(r"(?m)^  dynasty: (.+)$", block)
                title = (title_m.group(1).strip() if title_m else "无题").strip("\"'")
                author = (author_m.group(1).strip() if author_m else "佚名").strip("\"'")
                dynasty = (dynasty_m.group(1).strip() if dynasty_m else "").strip("\"'")
                tags = re.findall(r"(?m)^  - (.+)$", block)
                # tags section is multi; better parse between tags: and next key
                tags_block = re.search(
                    r"(?ms)^  tags:\n((?:  - .+\n)*)", block
                )
                tag_list = []
                if tags_block:
                    tag_list = re.findall(r"(?m)^  - (.+)$", tags_block.group(1))
                    tag_list = [t.strip().strip("\"'") for t in tag_list]
                new_appr = short_appreciation(title, author, dynasty, tag_list, layer)
                new_line = "  appreciation: " + json.dumps(new_appr, ensure_ascii=False)
                block = (
                    block[: m_appr.start()]
                    + new_line
                    + "\n"
                    + block[m_appr.end() :].lstrip("\n")
                )
                # careful: m_appr.end may leave rest; rebuild cleaner
                block = re.sub(
                    r"(?m)^  appreciation: .*$",
                    "  appreciation: " + json.dumps(new_appr, ensure_ascii=False),
                    block,
                    count=1,
                )
                changed += 1

        out.append(block)
        i += 2

    path.write_text("".join(out), encoding="utf-8")
    print(f"[poems] {path.name}: replaced {changed} template appreciations")
    return changed


def main() -> None:
    print("ROOT", ROOT)
    rebuild_authors()
    append_formulas()
    patch_poems_yaml(SOURCES / "poems_extended.yaml", TEMPLATE_EXT, "extended")
    patch_poems_yaml(SOURCES / "poems_explore.yaml", TEMPLATE_EXP, "explore")
    print("done. next: dart run tools/poem_importer/bin/poem_importer.dart import-all")


if __name__ == "__main__":
    main()
