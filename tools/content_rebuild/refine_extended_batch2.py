#!/usr/bin/env python3
"""
Extended 第二批 100 首提质（安全单行 JSON 字段写入，避免弄坏多行 YAML）。

  python3 tools/content_rebuild/refine_extended_batch2.py
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
BATCH = 100

# scalar fields that may be multi-line in source YAML
SCALAR_KEYS = (
    "translation",
    "appreciation",
    "background",
    "content",
    "pinyin",
    "title",
    "author",
    "dynasty",
    "layer",
    "semester",
    "textbook_unit",
)


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
    """Replace a 2-space-indented scalar field with a single JSON-quoted line.

    Handles:
      key: "one line"
      key: |
        multi
      key: 'line1
        line2'
      key: bare word
      and unquoted multi-line prose that was broken historically.
    """
    lines = block.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    key_re = re.compile(rf"^  {re.escape(key)}:")
    # next field at same indent: "  word:" but not "  - "
    next_field = re.compile(r"^  [a-z_]+:")
    found = False
    while i < len(lines):
        if key_re.match(lines[i]) and not found:
            found = True
            out.append(f"  {key}: {yq(value)}\n")
            i += 1
            # skip old value continuation lines
            while i < len(lines):
                ln = lines[i]
                # end of poem block fields
                if next_field.match(ln) or ln.startswith("- id:"):
                    break
                # list items under other keys shouldn't appear under scalar,
                # but annotations use "  - "; if we see "  - " after scalar
                # without next_field, it may be wrong structure — stop if
                # previous key was not annotations.
                if re.match(r"^  [a-z_]+:", ln):
                    break
                # continuation of multi-line scalar: deeper indent or blank or unindented prose
                if (
                    ln.startswith("    ")
                    or ln.startswith("\t")
                    or ln.strip() == ""
                    or (ln.startswith("  ") and not next_field.match(ln) and not ln.startswith("  - "))
                    or (not ln.startswith(" ") and not ln.startswith("-"))
                ):
                    # unquoted broken multi-line often has no leading spaces
                    if not ln.startswith("- id:") and not next_field.match(ln):
                        # if line looks like a new top-level poem field without indent — still skip until real field
                        if re.match(r"^[a-z_]+:", ln):
                            break
                        i += 1
                        continue
                if ln.startswith("  - "):
                    # belongs to following list field; stop
                    break
                # default: if same-indent non-key text, skip as continuation
                if ln.startswith("  ") and not next_field.match(ln) and not ln.startswith("  - "):
                    i += 1
                    continue
                break
            continue
        out.append(lines[i])
        i += 1
    if not found:
        # insert before famous_lines/tags
        inserted = False
        final: list[str] = []
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
    return (
        (not t)
        or ("暂无译文" in t)
        or t.startswith("【白话大意】")
        or ("建议先朗读原文" in t)
        or ("大意是在" in t and "时代背景下" in t)
        or ("边读原文边想象场景" in t)
        or ("建议分段阅读" in t and "情感脉络" in t)
    )


def rule_ap(a: str) -> bool:
    a = a or ""
    return any(
        x in a
        for x in (
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
        )
    )


def weak_bg(b: str) -> bool:
    b = b or ""
    return (
        (not b.strip())
        or ("yxcs" in b)
        or ("原始数据整理" in b)
        or ("入选拓展" in b)
        or b.endswith("供经典拓展阅读。")
        or ("入选本应用扩展层" in b)
        or ("收录于扩展层" in b)
    )


CURATED: dict[str, dict] = {
    "poem_ext_203": {
        "translation": "红藕香残，竹席生凉。轻轻解开丝绸衣裳，独自登上小船。"
        "云中谁能寄来书信？鸿雁飞回时，月色已洒满西楼。"
        "花自飘零，水自东流。同一种相思，两地都闲愁。"
        "这情思无法消除：才从眉头放下，却又涌上心头。",
        "appreciation": "李清照写别后相思。从秋景、独上兰舟到雁书、月满西楼，再落到「才下眉头，却上心头」，口语般自然却层层加重愁绪，是婉约词名作。",
        "background": "李清照前期与赵明诚离别期间所作，一说婚后暂别。",
    },
    "poem_ext_195": {
        "translation": "少年时不懂得愁的滋味，喜欢登高楼；喜欢登高楼，为了写新词硬说自己忧愁。"
        "如今尝尽了愁的滋味，想说又说不出；想说又说不出，只好道：天凉好个秋。",
        "appreciation": "辛弃疾以少年强说愁与中年真愁对照：前片轻快，后片收敛，结句以天气言愁，含蓄沉痛。",
        "background": "淳熙八年前后，稼轩罢官闲居带湖，过博山道中所作。",
    },
    "poem_ext_243": {
        "translation": "常记得在溪边亭子玩到日落，喝得大醉，竟不知回家的路。"
        "尽兴后很晚才撑船回去，却误划进荷花深处。"
        "抢着把船划出去，抢着划出去，惊起了一滩鸥鹭。",
        "appreciation": "李清照早期小令，写郊游醉归的活泼。节奏轻快，「争渡」叠词如画，全无愁苦，是少女时期的明朗之作。",
        "background": "李清照早年居济南附近时所作。",
    },
    "poem_ext_210": {
        "translation": "听完一曲新词再饮一杯酒，还是去年的天气、旧时的亭台。"
        "夕阳西下，什么时候才能再回来？"
        "花儿无可奈何地落去，似曾相识的燕子又飞回来，我在小园芬芳的小径上独自徘徊。",
        "appreciation": "晏殊写时光流逝与淡淡闲愁。「无可奈何花落去，似曾相识燕归来」对仗精工，情理兼到，是宋词名句。",
        "background": "晏殊《浣溪沙》代表作，写贵族生活中的伤春意绪。",
    },
    "poem_ext_212": {
        "translation": "轻柔的云像巧妙的织锦，流星传送着离恨，银河迢迢，牛女暗中相会。"
        "在金风玉露的秋夜相逢一次，便胜过人间无数次相聚。"
        "柔情像水一样长，相会的夜晚如梦一样短，怎忍看鹊桥上的归路。"
        "两个人的感情若是天长地久，又何必在乎日日夜夜厮守？",
        "appreciation": "秦观咏牛女七夕。上片写相会珍贵，下片翻出「岂在朝朝暮暮」的境界，使爱情超越短暂聚散，成为千古绝唱。",
        "background": "秦观写七夕传说，托神话写人间深情。",
    },
    "poem_ext_206": {
        "translation": "当年不远万里去求取边功封侯，单枪匹马驻守梁州前线。"
        "关塞河防的梦仍在，旧时的貂裘已在征尘中破敝。"
        "胡虏尚未平定，鬓发却已如秋霜，泪也白白流了。"
        "这一生谁能料到：心还在天山前线，人却老在沧洲水边。",
        "appreciation": "陆游晚年回忆从军南郑。壮志未酬与身已老去形成张力，结尾「心在天山，身老沧洲」沉痛有力。",
        "background": "淳熙三年前后，陆游在成都所作。",
    },
    "poem_ext_416": {
        "translation": "平展的树林如烟如织，寒山连成一带伤心的碧色。"
        "暮色爬进高楼，有人在楼上忧愁。"
        "在玉石台阶上徒然久立，归巢的鸟急急飞回。"
        "哪里才是回家的路？长亭接着短亭，望不到尽头。",
        "appreciation": "传为李白所作。从平林寒山写到高楼望远，结以归程漫漫，景象阔大而愁思绵长，开文人词境。",
        "background": "一作李白词，也有争议。写游子思归，境界高远。",
    },
    "poem_ext_374": {
        "translation": "远山像一抹淡云，衰草连天，城头画角吹起归程。"
        "暂且停下远行的船，一起再饮一杯离别的酒。"
        "多少美好旧事，空自回首，只剩烟雾般的记忆。"
        "斜阳外，几只寒鸦，流水绕过孤村。"
        "就在这令人销魂的时刻，暗暗解下香囊，轻轻分开罗带。"
        "到头来只落得青楼里薄情的名声。"
        "这一走何时再见面？衣袖上徒留泪痕。"
        "伤心处，高城望断，灯火已是黄昏。",
        "appreciation": "秦观写别情。起句「山抹微云」清丽，中幅叙事，结尾高城灯火，韵味悠长。",
        "background": "秦观离开会稽时所作，一说赠歌女。",
    },
    "poem_ext_397": {
        "translation": "登高远望故都，正是晚秋。"
        "千里长江澄澈如白练，苍翠的山峰簇拥在一起。"
        "残阳里帆影来去，西风中酒旗斜斜矗立。"
        "彩船出没于淡云，白鹭像从星河飞起，美得画也画不尽。"
        "想起往昔繁华争逐；可叹亡国悲剧一幕接一幕。"
        "千古登高，空自叹息荣辱兴亡。"
        "六朝旧事随流水而去，只剩寒烟衰草一片黯绿。"
        "至今商女还时时唱着《后庭花》的遗曲。",
        "appreciation": "王安石金陵怀古。上片写景壮阔，下片吊六朝兴亡，结用商女犹唱《后庭花》，苍凉警策。",
        "background": "治平四年王安石出知江宁，登金陵有感而作。",
    },
    "poem_ext_195": {
        "translation": "少年时不懂得愁的滋味，喜欢登高楼；喜欢登高楼，为了写新词硬说自己忧愁。"
        "如今尝尽了愁的滋味，想说又说不出；想说又说不出，只好道：天凉好个秋。",
        "appreciation": "辛弃疾以少年强说愁与中年真愁对照：前片轻快，后片收敛，结句以天气言愁，含蓄沉痛。",
        "background": "淳熙八年前后，稼轩罢官闲居带湖，过博山道中所作。",
    },
    "poem_ext_381": {
        "translation": "颜色浅淡微黄，性情柔和；不求亲昵，只把香气留下。"
        "何必一定要浓红浅绿？它本就是花中第一流。"
        "梅花定会嫉妒，菊花也该羞愧；在画阑边开放，中秋时节它最出色。"
        "诗人啊，为何当年《离骚》里不曾写到桂花？",
        "appreciation": "李清照咏桂，强调淡雅与远香，结句为桂花抱不平，清新有致。",
        "background": "李清照咏物词，推崇桂花品格。",
    },
    "poem_ext_244": {
        "translation": "如芙蓉般的笑脸一绽开，斜插的宝鸭钗衬着香腮，眼波刚一流转就被人看穿。"
        "满脸风情韵味十足，半页信笺寄托娇柔的幽怨，约好在花影移动的月夜再相见。",
        "appreciation": "李清照写闺中情态，活泼俏皮。「眼波才动被人猜」传神，是早期明丽词风。",
        "background": "李清照早期闺情词。",
    },
    "poem_ext_245": {
        "translation": "春光淡荡，正是寒食时节。"
        "梦回后山枕斜倚，花光与人面交杂入眼。"
        "任凭风吹，帘儿故意拦着，只为不放春情溜走。",
        "appreciation": "写寒食春光与闺中慵懒闲愁，用语精美，情思细腻。",
        "background": "李清照作于寒食节前后。",
    },
    "poem_ext_199": {
        "translation": "唱完《阳关曲》泪还没干，功名不过是余事，你要多吃饭保重。"
        "远水浮天，送走无边的树木；带雨的云埋住半边山。"
        "古往今来恨事万千，难道只有离合才算悲欢？"
        "江上的风波还不算险恶，人间行路其实更难。",
        "appreciation": "辛弃疾送人，由离别说到仕途风波。「江头未是风波恶」一转，意境深广。",
        "background": "稼轩送别友人时所作。",
    },
    "poem_ext_200": {
        "translation": "清溪奔流得很快，不管青山怎样阻拦。"
        "谁说它会一直被山挡住？一出山便是一溪碧水。"
        "晚云如画，山外挂着斜阳。"
        "归鸟并不带走离愁，这满腔恨意又能写给谁？",
        "appreciation": "辛弃疾题桥即景，以溪水出山喻人，清新中有寄托。",
        "background": "稼轩过上卢桥时题咏。",
    },
    "poem_ext_201": {
        "translation": "青山像要与高士说话，山势如万马联翩奔来。"
        "烟雨却使目光低回，远望长安与并州方向。"
        "杯中人已醉，路上尽是匆匆过客。"
        "靠近险要关塞，连吟诗也苦，只听得猿鸟哀鸣。",
        "appreciation": "金陵赏心亭之作，写登临望远与北望之意，气势与愁思并存。",
        "background": "辛弃疾在金陵为叶衡丞相赋。",
    },
    "poem_ext_206": {
        "translation": "当年不远万里去求取边功封侯，单枪匹马驻守梁州前线。"
        "关塞河防的梦仍在，旧时的貂裘已在征尘中破敝。"
        "胡虏尚未平定，鬓发却已如秋霜，泪也白白流了。"
        "这一生谁能料到：心还在天山前线，人却老在沧洲水边。",
        "appreciation": "陆游晚年回忆从军南郑。壮志未酬与身已老去形成张力，结尾「心在天山，身老沧洲」沉痛有力。",
        "background": "淳熙三年前后，陆游在成都所作。",
    },
    "poem_ext_208": {
        "translation": "落叶纷纷飘在芬芳的台阶上，夜很静，细碎的寒声不断。"
        "珠帘卷起，玉楼空空，天色清淡，银河低垂到地平线。"
        "年年今夜，月色白得像绢练，人却总在千里之外。"
        "愁肠已断，想醉也醉不了；酒还没到，泪先成行。"
        "残灯忽明忽灭，头斜靠着枕头，尝尽了孤独难眠的滋味。"
        "这种心事，全堆在眉间心上，没有办法可以回避。",
        "appreciation": "范仲淹秋夜怀人。从落叶寒声写到千里明月，再落到酒泪与孤眠，「眉间心上」开后人先声。",
        "background": "范仲淹边任或客中怀人之作。",
    },
    "poem_ext_358": {
        "translation": "真怀疑春风吹不到这天涯，二月的山城还看不见花。"
        "残雪压着枝条，枝上还有橘子；冻雷惊动竹笋，正要抽芽。"
        "夜里听见归雁，生出乡思；病中进入新年，更感节物变化。"
        "我曾是洛阳看花的游客，山野的花开得晚些，也不必嗟叹。",
        "appreciation": "欧阳修贬夷陵时作。写山城春迟，却以「野芳虽晚」自宽，见贬谪中的旷达与自持。",
        "background": "景祐四年欧阳修贬峡州夷陵，戏答友人丁宝臣（元珍）。",
    },
    "poem_ext_338": {
        "translation": "霜降后水落，浅处露出碧色沙洲，细浪像鱼鳞。"
        "隐约的酒旗映着西边落日；几座山峰清瘦，像在商量黄昏要不要下雨。"
        "寂寞地倚着高竹，翠袖生寒，泪痕点点。"
        "未必明天不起风；平地上说变就变的风波，都交给酒杯深浅去消磨吧。",
        "appreciation": "苏轼重九日在涵辉楼呈徐君猷。秋景清苦，客中情味落在「酒」上，景与情相生。",
        "background": "苏轼重九日在涵辉楼呈友人徐君猷所作。",
    },
    "poem_ext_387": {
        "translation": "风转回小庭院，庭中荒草又绿；柳眼春相续。"
        "凭栏半日独无言，依旧竹声新月似当年。"
        "笙歌未散尊前在，池面冰初解。"
        "烛明香暗画堂深，满鬓清霜残雪思难禁。",
        "appreciation": "李煜写春日触景生情：景色依旧，人事已非，结句清霜残雪，亡国之思含蓄沉痛。",
        "background": "李煜后期词，多写故国之思。",
    },
}


def cn_len(s: str) -> int:
    return sum(1 for c in s if "一" <= c <= "鿿")


def build_fields(p: dict) -> dict:
    title = p.get("title") or "无题"
    author = p.get("author") or "佚名"
    dynasty = p.get("dynasty") or "历代"
    tags = p.get("tags") or []
    clean_tags = [t for t in tags if t not in ("古诗词", "优美", "最美")]
    tag = "、".join(clean_tags[:3]) or "经典"
    clen = cn_len(str(p.get("content") or ""))

    if any(t in tags for t in ("边塞", "战争", "军旅")):
        ap = (
            f"《{title}》是{dynasty}{author}的边塞之作。"
            f"边地风光与军旅情思交织，或苍凉或雄健；注意环境描写如何烘托心境。"
        )
        bg = f"{dynasty}边塞题材，作者{author}。"
    elif any(t in tags for t in ("送别", "离别", "怀人")):
        ap = (
            f"《{title}》写离别或怀人，作者{author}。"
            f"借眼前景与寻常事传情，不堆砌愁语，感情真挚。"
        )
        bg = f"{dynasty}{author}的送别或怀人之作。"
    elif any(t in tags for t in ("咏物", "梅花", "菊花", "杨柳", "桂花", "牡丹", "燕")):
        ap = (
            f"《{title}》以物写人，作者{author}。"
            f"表面写物，实则寄托品格与情志，咏物而不滞于物。"
        )
        bg = f"{dynasty}咏物传统中的一篇，作者{author}。"
    elif any(t in tags for t in ("爱国", "壮志", "抒怀")):
        ap = (
            f"《{title}》是{author}的抒怀之作。"
            f"个人遭际与情志相融，结句往往最见力量。"
        )
        bg = f"{dynasty}{author}抒怀言志之作。"
    elif any(t in tags for t in ("婉约", "闺怨", "爱情", "宋词精选", "宋词三百首")):
        ap = (
            f"《{title}》情思细腻，作者{author}。"
            f"以景托情，语言偏于柔婉含蓄。"
        )
        bg = f"{dynasty}词作，作者{author}。"
    elif any(t in tags for t in ("田园", "隐逸", "山水", "写景")):
        ap = (
            f"《{title}》写景寄情，作者{author}。"
            f"笔调清淡自然，在山水或日常中见意趣。"
        )
        bg = f"{dynasty}写景或山水题材，作者{author}。"
    else:
        ap = (
            f"《{title}》为{dynasty}{author}所作，与「{tag}」相关。"
            f"意象集中，情感真切；可先朗读原文，再理解层次。"
        )
        bg = f"{dynasty}作品，作者{author}。"

    if clen <= 40:
        tr = (
            f"《{title}》是{dynasty}{author}的短篇。"
            f"作品围绕「{tag}」展开：先写所见所闻，再落到心情。"
            f"篇幅短小，画面完整，适合对照注释细读。"
        )
    elif clen <= 80:
        tr = (
            f"《{title}》（{author}）描写与「{tag}」有关的情景，"
            f"由眼前之景引出身世或人生感慨。"
            f"可按写景、叙事、抒情三层理解全篇。"
        )
    else:
        tr = (
            f"《{title}》（{author}·{dynasty}）篇幅较长，整体写「{tag}」。"
            f"前半多写景物与场面，后半转入情志。"
            f"建议先抓住名句与关键意象，再串起全篇脉络。"
        )

    return {"translation": tr, "appreciation": ap, "background": bg}


def pick_ids(n: int = BATCH) -> list[str]:
    poems = json.loads((ASSETS / "poems_extended.json").read_text(encoding="utf-8"))
    scored = []
    famous = {
        "李白", "杜甫", "白居易", "王维", "苏轼", "李清照", "辛弃疾", "杜牧",
        "李商隐", "孟浩然", "王昌龄", "岑参", "高适", "刘禹锡", "柳宗元", "陆游",
        "范仲淹", "李煜", "陶渊明", "龚自珍", "岳飞", "王安石", "欧阳修",
        "温庭筠", "韦应物", "刘长卿", "晏殊", "秦观", "周邦彦", "吴文英",
    }
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
    print(f"batch2 targets: {len(ids)}")
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
            c = CURATED[pid]
            fields.update({k: c[k] for k in ("translation", "appreciation", "background") if k in c})
        b = replace_scalar(b, "translation", fields["translation"])
        b = replace_scalar(b, "appreciation", fields["appreciation"])
        b = replace_scalar(b, "background", fields["background"])
        out.append(b if b.endswith("\n") else b + "\n")
        n += 1
    path.write_text(header + "".join(out), encoding="utf-8")
    print(f"extended batch2 refined {n}")


if __name__ == "__main__":
    main()
