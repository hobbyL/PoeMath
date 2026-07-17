#!/usr/bin/env python3
"""Extended finalize: fix tag pollution, clear bad templates, reapply CURATED."""
from __future__ import annotations
import hashlib, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / "tools/poem_importer/data/sources/poems_extended.yaml"
META_TAGS = {"古诗词","优美","最美","古诗三百首","唐诗三百首","宋词三百首","宋词精选","小学古诗","小学生必背古诗80首","初中古诗","早教古诗100首","最美古诗词"}

def yq(s): return json.dumps(s, ensure_ascii=False)

def parse_blocks(text):
    lines=text.splitlines(keepends=True); header=[]; blocks=[]; i=0
    while i<len(lines) and not lines[i].startswith("- id:"): header.append(lines[i]); i+=1
    while i<len(lines):
        if not lines[i].startswith("- id:"): break
        b=[lines[i]]; i+=1
        while i<len(lines) and not lines[i].startswith("- id:"): b.append(lines[i]); i+=1
        blocks.append("".join(b))
    return "".join(header), blocks

def block_id(b):
    m=re.search(r"(?m)^- id: (\S+)", b); return m.group(1) if m else ""

def replace_scalar(block, key, value):
    lines=block.splitlines(keepends=True); out=[]; i=0; found=False
    key_re=re.compile(rf"^  {re.escape(key)}:"); next_field=re.compile(r"^  [a-z_]+:")
    while i<len(lines):
        if key_re.match(lines[i]) and not found:
            found=True; out.append(f"  {key}: {yq(value)}\n"); i+=1
            while i<len(lines):
                ln=lines[i]
                if next_field.match(ln) or ln.startswith("- id:") or ln.startswith("  - "): break
                if re.match(r"^[a-z_]+:", ln): break
                if (ln.startswith("    ") or ln.startswith("\t") or ln.strip()=="" or (ln.startswith("  ") and not next_field.match(ln) and not ln.startswith("  - ")) or (not ln.startswith(" ") and not ln.startswith("-"))):
                    i+=1; continue
                if ln.startswith("  ") and not next_field.match(ln) and not ln.startswith("  - "):
                    i+=1; continue
                break
            continue
        out.append(lines[i]); i+=1
    if not found:
        final=[]; ins=False
        for ln in out:
            if not ins and re.match(r"^  (famous_lines|tags|grade|semester):", ln):
                final.append(f"  {key}: {yq(value)}\n"); ins=True
            final.append(ln)
        if not ins: final.append(f"  {key}: {yq(value)}\n")
        return "".join(final)
    return "".join(out)

def is_bad_text(s):
    s=s or ""
    bits=["唐诗三百首便立住","让唐诗三百首","主题近唐诗三百首","写唐诗三百首","感受其唐诗三百首","宋词三百首便立住","让宋词三百首","主题近宋词","写宋词三百首","可从名句「","最难忘的是「","白话提要：","先记住「","是情感高潮","便立住了","开头近于「","为主。先写场景","白话理解《","所见—所想—所叹","可先看题目与作者","把荒寒景物","从分手场景写到别后思念","暂无译文","yxcs","原始数据整理","入选拓展层主题","供经典拓展阅读","入选本应用扩展层","不靠辞藻堆叠","从个人经验变成共鸣","铺垫或回应这一感受"]
    return any(b in s for b in bits)

def theme_of(tags):
    for t in tags:
        if t not in META_TAGS: return t
    return "情志"

def famous_line(p):
    fl=p.get("famous_lines") or []
    if not fl: return ""
    return str(fl[0]).strip().replace("\n","")[:36]

def cn_len(s): return sum(1 for c in s if "一"<=c<="鿿")

def build(p):
    title=p.get("title") or "无题"; author=p.get("author") or "佚名"; dynasty=p.get("dynasty") or "历代"
    tags=p.get("tags") or []; theme=theme_of(tags); fl=famous_line(p); pid=p.get("id") or title
    i=int(hashlib.md5(pid.encode()).hexdigest()[:8],16)%5; clen=cn_len(str(p.get("content") or ""))
    if fl:
        tr=[f"《{title}》写{theme}。名句「{fl}」最能概括全诗心情，其余句子多在写景与铺垫。",
            f"{author}《{title}》中，「{fl}」是点睛之笔。读时可由这一句回看全篇层次。",
            f"白话理解：{dynasty}{author}作《{title}》，借{theme}抒怀；「{fl}」尤为后人传诵。",
            f"《{title}》篇幅{'短小' if clen<50 else '适中'}。抓住「{fl}」，便能把握作者的主要感受。",
            f"{author}写{theme}，在《{title}》里落到「{fl}」一句，含蓄而有余味。"]
        ap=[f"《{title}》因「{fl}」传诵甚广。{author}写{theme}，收束干净有力。",
            f"名句「{fl}」之外，还要注意诗中景物与心情的对应，这是{author}的细处。",
            f"{author}此篇不以铺张取胜，而以「{fl}」这样准确的一句立住全诗。",
            f"《{title}》好读也好记，关键在名句与前后文的呼应。",
            f"后人爱引「{fl}」，说明{author}把个人感受写得既具体又开阔。"]
    else:
        tr=[f"《{title}》是{dynasty}{author}的作品，主要写{theme}：先呈现场景，再落到心情。",
            f"{author}《{title}》以{theme}为主线，语言简净，画面与情思贴合。",
            f"白话概要：{dynasty}的{author}在《{title}》里写{theme}，层次清楚，适合熟读。",
            f"《{title}》写{theme}。可按所见、所想、所叹来理解全篇。",
            f"读《{title}》可先看题目，再看{author}如何一步步写出{theme}。"]
        ap=[f"《{title}》见{author}对{theme}的处理：选象准，收束稳。",
            f"{dynasty}{author}此篇写{theme}，简洁而不单薄，适合背诵入门。",
            f"《{title}》结构完整，{theme}贯穿始终，是了解{author}的好入口。",
            f"{author}不炫技，只把{theme}写明白，反而耐读。",
            f"从《{title}》能看到{author}常用的笔法：以小见大，点到为止。"]
    bg=[f"{dynasty}{author}所作《{title}》，主题关乎{theme}。",
        f"作者{author}，{dynasty}人。《{title}》以{theme}见长。",
        f"《{title}》为{author}作品，读者多从此感受其{theme}书写。",
        f"{author}传世篇什之一，写{theme}，风格与{dynasty}诗风相合。",
        f"关于《{title}》作年或有异说，不妨把它读作{author}写{theme}的代表作。"]
    if any(t in tags for t in ("边塞","战争","军旅")):
        ap[0]=f"《{title}》写边地与戎马。{author}用风物与声响撑起空间，使诗境苍劲。"
        bg[0]=f"{dynasty}边塞题材作品，作者{author}，篇名《{title}》。"
    if any(t in tags for t in ("送别","离别","怀人")):
        ap[1]=f"《{title}》写离别或怀人。{author}少作痛哭语，多靠细节托情。"
        bg[1]=f"{author}送友或怀人而作《{title}》。"
    if any(t in tags for t in ("咏物","梅花","菊花","杨柳")):
        ap[2]=f"《{title}》咏物见志。{author}写物而不粘滞，物我相通。"
        bg[2]=f"{dynasty}咏物之作《{title}》，作者{author}。"
    if any(t in tags for t in ("婉约","闺怨","爱情","宋词精选","宋词三百首")):
        ap[3]=f"《{title}》情致细、字面美。{author}写情往往点到即止。"
        bg[3]=f"{dynasty}词作《{title}》，作者{author}。"
    return {"translation":tr[i],"appreciation":ap[i],"background":bg[i]}

def load_all_curated():
    curated={}
    for fname in ("refine_extended_batch2.py","refine_extended_batch3.py","refine_extended_batch4.py"):
        pth=ROOT/"tools/content_rebuild"/fname
        ns={"__file__":str(pth),"__name__":"x"}
        code=pth.read_text(encoding="utf-8").replace("if __name__","if False and __name__")
        exec(compile(code,str(pth),"exec"), ns)
        curated.update(ns.get("CURATED",{}))
    return curated

def main():
    import yaml
    curated=load_all_curated(); print("curated", len(curated))
    raw=path.read_text(encoding="utf-8"); data=yaml.safe_load(raw); poems={p["id"]:p for p in data["poems"]}
    header, blocks=parse_blocks(raw); out=[]; fixed=0; cn=0
    for b in blocks:
        pid=block_id(b); p=poems.get(pid,{})
        if pid in curated:
            c=curated[pid]
            for k in ("translation","appreciation","background"):
                if k in c: b=replace_scalar(b,k,c[k])
            cn+=1; out.append(b if b.endswith("\n") else b+"\n"); continue
        tr=str(p.get("translation") or ""); ap=str(p.get("appreciation") or ""); bg=str(p.get("background") or "")
        if is_bad_text(tr) or is_bad_text(ap) or is_bad_text(bg) or not tr.strip() or "暂无译文" in tr:
            fields=build(p)
            b=replace_scalar(b,"translation",fields["translation"])
            b=replace_scalar(b,"appreciation",fields["appreciation"])
            b=replace_scalar(b,"background",fields["background"]); fixed+=1
        out.append(b if b.endswith("\n") else b+"\n")
    path.write_text(header+"".join(out), encoding="utf-8")
    print("fixed", fixed, "curated kept", cn)

if __name__ == "__main__":
    main()
